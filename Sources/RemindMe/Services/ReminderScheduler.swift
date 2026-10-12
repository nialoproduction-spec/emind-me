import Foundation
import SwiftData
import Combine
import AppKit

/// What the scheduler needs from the screen: show / hide the live reminder
/// and the end-of-day overlay. `ReminderPanelController` is the real one;
/// tests swap in a fake so the timing logic runs without any windows.
@MainActor
protocol LiveReminderPresenting: AnyObject {
    func presentLiveReminder()
    func dismissLiveReminder()
    func presentOverlay()
    func dismissOverlay()
}

extension ReminderPanelController: LiveReminderPresenting {}

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
    private var wakeObserver: NSObjectProtocol?
    private var autoCollapseTask: Task<Void, Never>?

    private let tickInterval: TimeInterval = 20
    let snoozeInterval: TimeInterval = 5 * 60
    let suppressedRetryInterval: TimeInterval = 45
    private let liveReminderVisibleDuration: TimeInterval = 20

    // Injected so tests can drive time, the screen, and settings directly.
    private let presenter: LiveReminderPresenting
    private let clock: @MainActor () -> Date
    private let shouldSuppress: @MainActor () -> Bool
    /// Read fresh on every use, so a change in Settings applies to the very
    /// next pop without needing a restart.
    private let escalationSettings: @MainActor () -> EscalationSettings

    private var escalation: EscalationSettings { escalationSettings() }

    init(
        presenter: LiveReminderPresenting? = nil,
        now: (@MainActor () -> Date)? = nil,
        shouldSuppress: (@MainActor () -> Bool)? = nil,
        escalationSettings: (@MainActor () -> EscalationSettings)? = nil
    ) {
        self.presenter = presenter ?? ReminderPanelController.shared
        self.clock = now ?? { Date.now }
        self.shouldSuppress = shouldSuppress ?? { FocusGuard.shouldSuppress() }
        self.escalationSettings = escalationSettings ?? { EscalationSettingsStore.shared.settings }
    }

    func start(modelContext: ModelContext) {
        attach(modelContext: modelContext)
        scheduleTimer()
        // Block-based observer: no Objective-C selector, nothing to unregister
        // by hand while the scheduler lives for the whole app session.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        tick() // catch up on anything due since the app last ran
    }

    /// Hooks up storage without starting the timer — `start` uses this, and
    /// tests call it directly, then drive `tick()` themselves.
    func attach(modelContext: ModelContext) {
        self.modelContext = modelContext
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

    // MARK: - Tick

    func tick() {
        guard let modelContext else { return }
        let now = clock()

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
        let current = clock()
        var next = item.computeNextFireDate(after: dueAt)
        if let candidate = next, candidate <= current {
            next = item.computeNextFireDate(after: current)
        }
        item.nextFireDate = next

        attemptPresent(occurrence)
    }

    private func attemptPresent(_ occurrence: Occurrence) {
        let current = clock()
        guard activeOccurrence == nil, !shouldSuppress() else {
            // Not shown — retry soon without spending one of the attempts.
            occurrence.nextEscalationAt = current.addingTimeInterval(suppressedRetryInterval)
            return
        }
        occurrence.remindersSentCount += 1
        if occurrence.firstFiredAt == nil { occurrence.firstFiredAt = current }
        occurrence.nextEscalationAt = current.addingTimeInterval(TimeInterval(escalation.intervalMinutes * 60))
        present(occurrence)
    }

    private func present(_ occurrence: Occurrence) {
        activeOccurrence = occurrence
        presenter.presentLiveReminder()

        autoCollapseTask?.cancel()
        let visibleFor = liveReminderVisibleDuration
        autoCollapseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(visibleFor))
            guard let self, !Task.isCancelled, self.activeOccurrence?.id == occurrence.id else { return }
            self.collapseWithoutResolving()
        }
    }

    /// A button was tapped: stop the auto-collapse so the panel stays up for
    /// the short reaction animation and the tap isn't lost if the 20-second
    /// timer happens to run out mid-reaction.
    func holdForReaction() {
        autoCollapseTask?.cancel()
    }

    /// Hides the live reminder but leaves its occurrence pending, so the
    /// escalation keeps going. What happens when nobody answers in time.
    func collapseWithoutResolving() {
        autoCollapseTask?.cancel()
        activeOccurrence = nil
        presenter.dismissLiveReminder()
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
        // A snooze must always come back. If this was the last allowed pop,
        // step the count back by one so the snoozed re-pop still happens —
        // otherwise the next check would see "out of attempts" and mark it
        // unfinished without ever showing it again.
        let maxPops = escalation.maxReminders
        if occurrence.remindersSentCount >= maxPops {
            occurrence.remindersSentCount = maxPops - 1
        }
        occurrence.nextEscalationAt = clock().addingTimeInterval(snoozeInterval)
        try? modelContext?.save()
        collapseWithoutResolving()
    }

    private func resolve(status: OccurrenceStatus) {
        guard let occurrence = activeOccurrence else { return }
        occurrence.status = status
        occurrence.resolvedAt = clock()
        occurrence.nextEscalationAt = nil
        try? modelContext?.save()
        collapseWithoutResolving()
    }

    // MARK: - End of day

    /// True once the day's chosen summary time has passed and it hasn't been
    /// shown yet today. "At or after", not "exactly at": if the Mac is asleep
    /// or the app is busy at 9:00 PM, the summary still appears the next time
    /// the scheduler checks, instead of being skipped for the whole day.
    nonisolated static func shouldShowEndOfDay(
        settings: EndOfDaySettings, now: Date, calendar: Calendar = .current
    ) -> Bool {
        guard settings.isEnabled else { return false }
        guard settings.lastShownDayKey != Occurrence.dayKey(for: now, calendar: calendar) else { return false }
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour = settings.hour
        comps.minute = settings.minute
        comps.second = 0
        guard let summaryTime = calendar.date(from: comps) else { return false }
        return now >= summaryTime
    }

    private func checkEndOfDay(now: Date) {
        guard !showEndOfDaySummary else { return }
        let settings = EndOfDaySettingsStore.shared.settings
        guard Self.shouldShowEndOfDay(settings: settings, now: now) else { return }

        EndOfDaySettingsStore.shared.settings.lastShownDayKey = Occurrence.dayKey(for: now)
        showEndOfDaySummary = true
        presenter.presentOverlay()
    }

    func dismissEndOfDaySummary() {
        showEndOfDaySummary = false
        presenter.dismissOverlay()
    }
}
