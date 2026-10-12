import Foundation
import SwiftData
import Combine
import AppKit

/// Drives everything time-based: noticing when a routine is due, popping the
/// live reminder, the escalation (count and interval are user-adjustable in
/// Settings — see `EscalationSettings`), snooze/done/skip, and the
/// end-of-day summary trigger.
///
/// Reliability design: every due time is an absolute `Date` stored on the
/// model (`Item.nextFireDate`, `Occurrence.nextEscalationAt`), never a
/// running countdown. A lightweight timer just polls "is anything's absolute
/// time now in the past?" every 20 seconds — cheap (a handful of date
/// comparisons), and immune to drift because it never accumulates elapsed
/// time itself. `NSWorkspace.didWakeNotification` forces an immediate check
/// on wake, so a catch-up happens the moment the Mac is usable again rather
/// than waiting up to 20s, and so a reminder that was due *during* sleep
/// fires once on wake instead of being silently lost or flooding with every
/// missed interval. Per the brief, nothing schedules the Mac to wake itself.
@MainActor
final class ReminderScheduler: ObservableObject {
    static let shared = ReminderScheduler()

    /// Non-nil while the live reminder (Done / Snooze / Skip) is on screen.
    @Published private(set) var activeOccurrence: Occurrence?
    /// Flips true when it's time to show the end-of-day summary.
    @Published var showEndOfDaySummary = false

    private var modelContext: ModelContext?
    private var tickTimer: Timer?
    private var autoCollapseTask: Task<Void, Never>?

    private let tickInterval: TimeInterval = 20
    private let snoozeInterval: TimeInterval = 5 * 60
    private let suppressedRetryInterval: TimeInterval = 45
    private let liveReminderVisibleDuration: TimeInterval = 20

    /// Read fresh each time rather than cached, so a change in Settings
    /// applies to the very next pop without needing a restart.
    private var escalation: EscalationSettings { EscalationSettingsStore.shared.settings }

    private init() {}

    func start(modelContext: ModelContext) {
        self.modelContext = modelContext
        scheduleTimer()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(handleWake), name: NSWorkspace.didWakeNotification, object: nil
        )
        tick() // catch up on anything due since the app last ran
    }

    private func scheduleTimer() {
        tickTimer?.invalidate()
        let timer = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = tickInterval / 4
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    @objc private func handleWake() {
        tick()
    }

    // MARK: - Tick

    private func tick() {
        guard let modelContext else { return }
        let now = Date.now

        let items = (try? modelContext.fetch(FetchDescriptor<Item>())) ?? []
        let allOccurrences = (try? modelContext.fetch(FetchDescriptor<Occurrence>())) ?? []
        var pendingByItemID: [UUID: Occurrence] = [:]
        for occurrence in allOccurrences where occurrence.status == .pending {
            guard let itemID = occurrence.item?.id else { continue }
            if let existing = pendingByItemID[itemID] {
                if occurrence.scheduledFireDate > existing.scheduledFireDate { pendingByItemID[itemID] = occurrence }
            } else {
                pendingByItemID[itemID] = occurrence
            }
        }

        for item in items {
            guard item.kind != .goal, item.isActive else { continue }

            if let occurrence = pendingByItemID[item.id] {
                guard let nextEscalation = occurrence.nextEscalationAt, nextEscalation <= now else { continue }
                if occurrence.remindersSentCount >= escalation.maxReminders {
                    finalizeUnfinished(occurrence)
                } else {
                    attemptPresent(occurrence)
                }
            } else if let nextFire = item.nextFireDate, nextFire <= now {
                fireNew(item: item, dueAt: nextFire)
            }
        }

        checkEndOfDay(now: now)
        try? modelContext.save()
    }

    private func fireNew(item: Item, dueAt: Date) {
        guard let modelContext else { return }
        let occurrence = Occurrence(item: item, scheduledFireDate: dueAt)
        modelContext.insert(occurrence)

        // Advance past this firing. If the Mac was asleep long enough that
        // the next computed time is itself already in the past, jump
        // forward from *now* instead — a long sleep should cost one missed
        // catch-up, not a backlog of simultaneous pops.
        var next = item.computeNextFireDate(after: dueAt)
        if let candidate = next, candidate <= .now {
            next = item.computeNextFireDate(after: .now)
        }
        item.nextFireDate = next

        attemptPresent(occurrence)
    }

    private func attemptPresent(_ occurrence: Occurrence) {
        guard activeOccurrence == nil, !FocusGuard.shouldSuppress() else {
            // Not shown — retry soon without spending one of the 3 attempts.
            occurrence.nextEscalationAt = Date.now.addingTimeInterval(suppressedRetryInterval)
            return
        }
        occurrence.remindersSentCount += 1
        if occurrence.firstFiredAt == nil { occurrence.firstFiredAt = .now }
        occurrence.nextEscalationAt = Date.now.addingTimeInterval(TimeInterval(escalation.intervalMinutes * 60))
        present(occurrence)
    }

    private func present(_ occurrence: Occurrence) {
        activeOccurrence = occurrence
        ReminderPanelController.shared.presentLiveReminder()

        autoCollapseTask?.cancel()
        let visibleFor = liveReminderVisibleDuration
        autoCollapseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(visibleFor))
            guard let self, !Task.isCancelled, self.activeOccurrence?.id == occurrence.id else { return }
            self.activeOccurrence = nil
            ReminderPanelController.shared.dismissLiveReminder()
        }
    }

    private func finalizeUnfinished(_ occurrence: Occurrence) {
        occurrence.status = .unfinished
        occurrence.nextEscalationAt = nil
    }

    // MARK: - User actions (from the live reminder's three buttons)

    func markDone() { resolve(status: .done) }
    func skip() { resolve(status: .skipped) }

    func snooze() {
        guard let occurrence = activeOccurrence else { return }
        occurrence.nextEscalationAt = Date.now.addingTimeInterval(snoozeInterval)
        try? modelContext?.save()
        dismissActive()
    }

    private func resolve(status: OccurrenceStatus) {
        guard let occurrence = activeOccurrence else { return }
        occurrence.status = status
        occurrence.resolvedAt = .now
        occurrence.nextEscalationAt = nil
        try? modelContext?.save()
        dismissActive()
    }

    private func dismissActive() {
        autoCollapseTask?.cancel()
        activeOccurrence = nil
        ReminderPanelController.shared.dismissLiveReminder()
    }

    // MARK: - End of day

    private func checkEndOfDay(now: Date) {
        let settings = EndOfDaySettingsStore.shared.settings
        guard settings.isEnabled, !showEndOfDaySummary else { return }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: now)
        guard comps.hour == settings.hour, comps.minute == settings.minute else { return }
        let todayKey = Occurrence.dayKey(for: now)
        guard settings.lastShownDayKey != todayKey else { return }

        EndOfDaySettingsStore.shared.settings.lastShownDayKey = todayKey
        showEndOfDaySummary = true
        ReminderPanelController.shared.presentOverlay()
    }

    func dismissEndOfDaySummary() {
        showEndOfDaySummary = false
        ReminderPanelController.shared.dismissOverlay()
    }
}
