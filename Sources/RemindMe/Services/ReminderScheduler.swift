import Foundation
import SwiftData
import Combine
import AppKit

/// What the scheduler needs from the screen: show / hide the live reminder
/// and the end-of-day overlay. `ReminderPanelController` is the real one;
/// tests swap in a fake so the timing logic runs without any windows.
@MainActor
protocol LiveReminderPresenting: AnyObject {
    /// Show the reminder (or bring it forward again for a nag).
    func presentLiveReminder()
    /// The reminder was answered: put it away.
    func dismissLiveReminder()
    /// Tuck an unanswered reminder out of sight during a Focus / full-screen
    /// app; `presentLiveReminder` brings it back.
    func suspendLiveReminder()
    func presentOverlay()
    func dismissOverlay()
}

extension ReminderPanelController: LiveReminderPresenting {}

/// Drives everything time-based: noticing when a routine is due, popping the
/// live reminder, the escalation (count and interval are user-adjustable in
/// Settings — see `EscalationSettings`), snooze/done/skip, and the
/// end-of-day summary trigger.
///
/// A live reminder stays on screen until it's answered with Done, Snooze or
/// Skip. While it waits, each escalation step nags in place: the face's mood
/// steps up and the panel comes forward. After the last step it's counted as
/// unfinished for the day (and stops nagging) but is still on screen to be
/// answered. During a Focus or a full-screen app it's tucked away, and comes
/// back when that ends.
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

    /// Non-nil while a live reminder (Done / Snooze / Skip) is waiting for an
    /// answer. Re-published on every nag so observers see the new mood.
    @Published private(set) var activeOccurrence: Occurrence?
    /// True while the waiting reminder is tucked away for a Focus / full screen.
    @Published private(set) var isLiveReminderSuspended = false
    /// Flips true when it's time to show the end-of-day summary.
    @Published var showEndOfDaySummary = false

    private var modelContext: ModelContext?
    private var tickTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?

    private let tickInterval: TimeInterval = 20
    let snoozeInterval: TimeInterval = 5 * 60
    let suppressedRetryInterval: TimeInterval = 45

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
        // Full-screen apps live in their own Space: re-check right away when
        // the Space changes, so a waiting reminder tucks away (or comes back)
        // promptly instead of on the next 20-second tick.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
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
        let suppressed = shouldSuppress()
        updateSuspension(suppressed: suppressed)

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
                    finalizeUnfinished(occurrence) // if it's the one on screen, it stays there
                } else if occurrence.id == activeOccurrence?.id {
                    nagInPlace(occurrence, suppressed: suppressed)
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
        isLiveReminderSuspended = false
        presenter.presentLiveReminder()
        // No auto-close: it stays until Done, Snooze or Skip.
    }

    /// The reminder is still on screen, unanswered, and the next escalation
    /// step is due: nag in place. The count goes up (so the face's mood steps
    /// up) and the panel comes forward. During a Focus / full screen it waits
    /// instead, without using up a step.
    private func nagInPlace(_ occurrence: Occurrence, suppressed: Bool) {
        let current = clock()
        guard !suppressed else {
            occurrence.nextEscalationAt = current.addingTimeInterval(suppressedRetryInterval)
            return
        }
        occurrence.remindersSentCount += 1
        occurrence.nextEscalationAt = current.addingTimeInterval(TimeInterval(escalation.intervalMinutes * 60))
        activeOccurrence = occurrence // re-publish: the menu bar face picks up the new mood
        presenter.presentLiveReminder()
    }

    /// Tuck the waiting reminder away while a Focus / full-screen app is up,
    /// and bring it back after. It's never dropped — only hidden.
    private func updateSuspension(suppressed: Bool) {
        guard activeOccurrence != nil else {
            isLiveReminderSuspended = false
            return
        }
        if suppressed, !isLiveReminderSuspended {
            isLiveReminderSuspended = true
            presenter.suspendLiveReminder()
        } else if !suppressed, isLiveReminderSuspended {
            isLiveReminderSuspended = false
            presenter.presentLiveReminder()
        }
    }

    /// The routine behind the reminder on screen is being deleted: close the
    /// reminder. Returns true if it was the one showing.
    @discardableResult
    func closeLiveReminder(belongingTo item: Item) -> Bool {
        guard let active = activeOccurrence,
              active.item?.persistentModelID == item.persistentModelID else { return false }
        closeLiveReminder()
        return true
    }

    /// Clears the answered reminder off the screen.
    private func closeLiveReminder() {
        activeOccurrence = nil
        isLiveReminderSuspended = false
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
        // Snoozing something already counted as unfinished puts it back in play.
        if occurrence.status == .unfinished { occurrence.status = .pending }
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
        closeLiveReminder()
    }

    private func resolve(status: OccurrenceStatus) {
        guard let occurrence = activeOccurrence else { return }
        occurrence.status = status
        occurrence.resolvedAt = clock()
        occurrence.nextEscalationAt = nil
        try? modelContext?.save()
        closeLiveReminder()
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
