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
    /// Flips true when it's time to show the weekly summary.
    @Published var showWeeklySummary = false
    /// Flips true at the goal check-in time: the panel asks Done / Not today.
    @Published var showGoalCheckIn = false
    /// Flips true when you're back and things came due while you were away
    /// (or the Mac was asleep or off): "You missed: …".
    @Published var showMissed = false
    /// A Done / Snooze / Skip pressed on the keyboard; the reminder card
    /// picks it up so it can play its reaction first.
    @Published private(set) var shortcutRequest: ShortcutRequest?

    enum ShortcutAction: Equatable { case done, snooze, skip }
    struct ShortcutRequest: Equatable {
        let id = UUID()
        let action: ShortcutAction
    }

    private var modelContext: ModelContext?
    private var tickTimer: Timer?
    private var wakeObservers: [NSObjectProtocol] = []
    private var wakeCatchUp: Task<Void, Never>?
    /// The timer last shown at the notch (id and state), so it's only redrawn on change.
    private var shownTimerKey: String?
    /// When the last check ran; a long gap means the Mac was asleep or off.
    private var lastTickAt: Date?
    private var spaceObserver: NSObjectProtocol?

    /// Short enough for reminders every few seconds; the tick is only a few
    /// date comparisons.
    private let tickInterval: TimeInterval = 5
    let suppressedRetryInterval: TimeInterval = 45

    // Injected so tests can drive time, the screen, and settings directly.
    private let presenter: LiveReminderPresenting
    private let clock: @MainActor () -> Date
    private let shouldSuppress: @MainActor () -> Bool
    /// Read fresh on every use, so a change in Settings applies to the very
    /// next pop without needing a restart.
    private let escalationSettings: @MainActor () -> EscalationSettings
    /// Nobody at the Mac (smart "hold while away").
    private let isAway: @MainActor () -> Bool
    /// Default snooze length, in minutes.
    private let defaultSnoozeMinutes: @MainActor () -> Int
    /// A timed pause just ended (re-schedules its notifications).
    private let resumed: @MainActor (Item) -> Void
    /// When (and whether) the weekly summary shows.
    private let weeklySettings: PersistedSettings<WeeklySummarySettings>
    /// When the daily goal check-in shows.
    private let goalNudgeSettings: PersistedSettings<GoalNudgeSettings>
    /// Shows a small popup (quiet reminders, the goal check-in).
    private let showNotice: @MainActor (NoticeContent) -> Void
    private let popupSettings: PersistedSettings<ReminderPopupSettings>
    /// What came due while nobody saw it.
    let missed: PersistedSettings<MissedList>
    /// Reminders ignored in a row (they come back louder).
    let ignored: PersistedSettings<IgnoreCounts>
    /// Done / Skip can be undone.
    let undo: UndoCenter

    /// A fire this late (the Mac was asleep or off) goes to the missed list.
    nonisolated static let lateAfter: TimeInterval = 120

    private var escalation: EscalationSettings { escalationSettings() }

    init(
        presenter: LiveReminderPresenting? = nil,
        now: (@MainActor () -> Date)? = nil,
        shouldSuppress: (@MainActor () -> Bool)? = nil,
        escalationSettings: (@MainActor () -> EscalationSettings)? = nil,
        isAway: (@MainActor () -> Bool)? = nil,
        defaultSnoozeMinutes: (@MainActor () -> Int)? = nil,
        resumed: (@MainActor (Item) -> Void)? = nil,
        weeklySettings: PersistedSettings<WeeklySummarySettings>? = nil,
        goalNudgeSettings: PersistedSettings<GoalNudgeSettings>? = nil,
        showNotice: (@MainActor (NoticeContent) -> Void)? = nil,
        popupSettings: PersistedSettings<ReminderPopupSettings>? = nil,
        missed: PersistedSettings<MissedList>? = nil,
        ignored: PersistedSettings<IgnoreCounts>? = nil,
        undo: UndoCenter? = nil
    ) {
        self.presenter = presenter ?? ReminderPanelController.shared
        self.clock = now ?? { Date.now }
        self.shouldSuppress = shouldSuppress ?? { FocusGuard.shouldSuppress() }
        self.escalationSettings = escalationSettings ?? { EscalationSettingsStore.shared.settings }
        self.isAway = isAway ?? { AwayDetector.isAway() }
        self.defaultSnoozeMinutes = defaultSnoozeMinutes ?? { AppSettings.snooze.value.defaultMinutes }
        self.resumed = resumed ?? { NotificationService.shared.schedule(for: $0) }
        self.weeklySettings = weeklySettings ?? AppSettings.weekly
        self.goalNudgeSettings = goalNudgeSettings ?? AppSettings.goalNudge
        self.showNotice = showNotice ?? { NoticePillController.shared.show($0) }
        self.popupSettings = popupSettings ?? AppSettings.reminderPopup
        self.missed = missed ?? AppSettings.missed
        self.ignored = ignored ?? AppSettings.ignored
        self.undo = undo ?? UndoCenter.shared
    }

    func start(modelContext: ModelContext) {
        attach(modelContext: modelContext)
        scheduleTimer()
        // Popups say whether they were ignored, so repeat offenders get louder.
        NoticePillController.shared.onOutcome = { [weak self] id, wasIgnored in
            self?.popupOutcome(itemID: id, ignored: wasIgnored)
        }
        // Block-based observer: no Objective-C selector, nothing to unregister
        // by hand while the scheduler lives for the whole app session.
        // Wake, screens back on, the user's session back, and Low Power Mode
        // changes all re-check at once: a reminder that came due while the Mac
        // slept lands on the "You missed" list without waiting for a restart.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification,
                     NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            wakeObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.caughtUpAfterWake() }
            })
        }
        wakeObservers.append(NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        })
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

    /// Restarts the tick timer if it has stopped. Returns true when it had to.
    @discardableResult
    func ensureTickRunning() -> Bool {
        guard tickTimer?.isValid != true else { return false }
        scheduleTimer()
        return true
    }

    // MARK: - Tick

    /// Called on wake. Checks now, logs a long sleep, and checks again a few
    /// seconds later, once the clock and network have settled.
    private func caughtUpAfterWake() {
        let now = clock()
        if Self.wasAsleep(lastTick: lastTickAt, now: now), let lastTickAt {
            let minutes = Int(now.timeIntervalSince(lastTickAt) / 60)
            HealthMonitor.log.value.add("Mac was asleep or off for \(minutes) min; checked for reminders that came due", at: now)
        }
        tick()
        wakeCatchUp?.cancel()
        wakeCatchUp = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self.tick()
        }
    }

    /// The tick runs every few seconds, so a gap of a minute or more means the
    /// Mac was asleep (or off) in between.
    nonisolated static func wasAsleep(lastTick: Date?, now: Date) -> Bool {
        guard let lastTick else { return false }
        return now.timeIntervalSince(lastTick) > 60
    }

    func tick() {
        guard let modelContext else { return }
        let now = clock()
        lastTickAt = now
        let suppressed = shouldSuppress()
        let away = isAway()
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

        // Deadlines past their day are over.
        for item in items where item.endedAt == nil {
            if let due = item.dueDate, Self.deadlineIsPast(due: due, now: now) {
                item.endedAt = now
                item.nextFireDate = nil
            }
        }

        // Timed pauses that have run out resume on their own.
        for item in items where item.kind != .goal {
            if let until = item.pausedUntil, until <= now {
                item.pausedUntil = nil
                item.isActive = true
                item.nextFireDate = item.computeNextFireDate(after: now)
                resumed(item)
            }
        }

        for item in items {
            guard item.kind != .goal, item.isActive else { continue }

            if let occurrence = pendingByItemID[item.id] {
                guard let nextEscalation = occurrence.nextEscalationAt, nextEscalation <= now else { continue }
                if occurrence.remindersSentCount >= escalation.maxReminders {
                    finalizeUnfinished(occurrence) // if it's the one on screen, it stays there
                } else if occurrence.id == activeOccurrence?.id {
                    nagInPlace(occurrence, held: suppressed || away)
                } else {
                    attemptPresent(occurrence, held: away)
                }
            } else if let nextFire = item.nextFireDate, nextFire <= now {
                if item.style == .justRemind {
                    fireQuietReminder(item: item, dueAt: nextFire, held: suppressed || away)
                } else {
                    fireNew(item: item, dueAt: nextFire, held: away)
                }
            }
        }

        checkTimers(now: now)
        checkMissed(held: suppressed || away)
        checkGoalNudge(now: now, items: items, occurrences: allOccurrences, held: suppressed || away)
        checkEndOfDay(now: now)
        checkWeeklySummary(now: now)
        try? modelContext.save()
    }

    private func fireNew(item: Item, dueAt: Date, held: Bool = false) {
        guard let modelContext else { return }
        let occurrence = Occurrence(item: item, scheduledFireDate: dueAt)
        modelContext.insert(occurrence)
        DeliveryLog.record(.fired, title: item.title, at: clock())

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
        // One-time: it has had its moment, so it leaves the list (its card
        // still waits for an answer).
        if item.onceAt != nil { item.endedAt = current }

        attemptPresent(occurrence, held: held)
    }

    /// The end of the deadline's day has passed.
    nonisolated static func deadlineIsPast(due: Date, now: Date, calendar: Calendar = .current) -> Bool {
        let dayAfter = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: due)) ?? due
        return now >= dayAfter
    }

    /// How many times it came due from `dueAt` up to `now` (at least 1):
    /// an every-40-minutes reminder through a night's sleep came due many times.
    nonisolated static func dueCount(of item: Item, from dueAt: Date, to now: Date) -> Int {
        var count = 1
        var cursor = dueAt
        while count < 500, let next = item.computeNextFireDate(after: cursor), next <= now {
            count += 1
            cursor = next
        }
        return count
    }

    /// A "just remind" routine came due: a small popup with a face and the
    /// title, nothing to answer. No occurrence is stored, so it never nags,
    /// never blocks its next firing, and never lands in the checklist.
    /// `held` (away, or a Focus / full-screen app): there's nobody to tell, so
    /// this one is simply skipped rather than queued up.
    private func fireQuietReminder(item: Item, dueAt: Date, held: Bool) {
        let current = clock()
        let count = Self.dueCount(of: item, from: dueAt, to: current)
        DeliveryLog.record(.fired, title: item.title, at: current)
        var next = item.computeNextFireDate(after: dueAt)
        if let candidate = next, candidate <= current {
            next = item.computeNextFireDate(after: current)
        }
        item.nextFireDate = next
        if item.onceAt != nil { item.endedAt = current }
        let detail = item.dueDate.map { Item.deadlineLine(due: $0, now: current) }
        // Nobody saw it (away, full screen, or it's late because the Mac was
        // asleep or off): it goes on the "You missed" list for when you're back.
        let late = current.timeIntervalSince(dueAt) > Self.lateAfter
        guard !held, !late else {
            DeliveryLog.record(.missed, title: item.title, at: current,
                               detail: late ? "Came due while the Mac was asleep or off" : "Held while away or in full screen")
            missed.value.add(title: item.title, dueAt: dueAt, count: count, detail: detail)
            return
        }
        var content = Self.popupContent(title: item.title,
                                        quote: detail ?? ReminderQuotes.quote(for: item.title, pick: Int.random(in: 0..<1000)),
                                        settings: popupSettings.value)
        content.itemID = item.id
        content.plainDetail = detail != nil
        if ignored.value.isLoud(item.id) {
            // Ignored again and again: it comes back louder and waits for a click.
            content.loud = true
            content.sticky = true
            content.detail = Self.loudLine(times: ignored.value.count(for: item.id))
        }
        DeliveryLog.record(.shown, title: item.title, at: current)
        showNotice(content)
    }

    nonisolated static func loudLine(times: Int) -> String {
        "Ignored \(times) times. Look at me!"
    }

    // MARK: - Task timers

    /// Called after a timer is answered or started, so the notch and the list
    /// catch up at once instead of on the next tick.
    func timersChanged() {
        checkTimers(now: clock())
    }

    /// At zero, a popup asks whether the task is done, and the panel opens
    /// with Done and Not yet. If nobody answers for a minute, the timer turns red.
    private func checkTimers(now: Date) {
        var timers = TaskTimers.store.value
        let changes = timers.advance(now: now)
        if !changes.isEmpty { TaskTimers.store.value = timers }
        for entry in changes.asking {
            DeliveryLog.record(.shown, title: entry.title, at: now, detail: "Time's up")
            showNotice(Self.popupContent(title: "\(entry.title): time's up",
                                         quote: "Done with it?", settings: popupSettings.value))
            let panel = ReminderPanelController.shared
            panel.show()
            panel.setExpanded(true)
            panel.keepOpenUntilClickAway()
        }
        for entry in changes.overdue {
            DeliveryLog.record(.missed, title: entry.title, at: now, detail: "No answer; counting on")
        }
        showTimerAtNotch()
    }

    /// The running timer at the notch: a countdown, then "done?", then red and counting up.
    private func showTimerAtNotch() {
        guard let entry = TaskTimers.store.value.current else {
            if shownTimerKey != nil {
                shownTimerKey = nil
                BreakIslandController.shared.hide()
            }
            return
        }
        let key = "\(entry.id)-\(entry.state.rawValue)"
        guard key != shownTimerKey else { return }
        shownTimerKey = key
        BreakIslandController.shared.show(Self.timerNotice(for: entry))
    }

    nonisolated static func timerNotice(for entry: TaskTimers.Entry) -> NoticeContent {
        switch entry.state {
        case .asking:
            return NoticeContent(title: "\(entry.title): done?", detail: "Time's up",
                                 face: .furious, tone: .away, sticky: true)
        case .overdue:
            return NoticeContent(title: entry.title, countUpFrom: entry.overdueAt ?? entry.endsAt,
                                 face: .furious, tone: .away, sticky: true)
        default:
            return NoticeContent(title: entry.title, countdownTo: entry.endsAt,
                                 face: .smug, tone: .work, sticky: true)
        }
    }

    // MARK: - Missed while away

    /// You're back (or the Mac woke up) and things came due meanwhile:
    /// the panel lists them, once.
    private func checkMissed(held: Bool) {
        guard !showMissed, !held, !missed.value.isEmpty, activeOccurrence == nil,
              !showGoalCheckIn, !showEndOfDaySummary, !showWeeklySummary else { return }
        showMissed = true
        presenter.presentOverlay()
    }

    func dismissMissed() {
        missed.value.entries = []
        guard showMissed else { return }
        showMissed = false
        presenter.dismissOverlay()
    }

    /// Something to put on the list from elsewhere (a render that finished
    /// while you were away).
    func noteMissed(title: String, at date: Date, detail: String? = nil) {
        missed.value.add(title: title, dueAt: date, detail: detail)
    }

    // MARK: - Ignored reminders

    /// How a reminder's popup went: ignored (timed out while you were busy)
    /// counts up; sent off (clicked) resets. Faded while you were away: no change.
    func popupOutcome(itemID: UUID, ignored wasIgnored: Bool) {
        let title = ((try? modelContext?.fetch(FetchDescriptor<Item>())) ?? [])
            .first { $0.id == itemID }?.title ?? "Reminder"
        if wasIgnored {
            ignored.value.ignored(itemID)
            DeliveryLog.record(.missed, title: title, at: clock(), detail: "Went by unanswered")
        } else {
            ignored.value.answered(itemID)
            DeliveryLog.record(.acknowledged, title: title, at: clock(), detail: "Clicked the popup")
        }
    }


    /// A reminder's popup: the title and a short quote, staying as long as
    /// Settings says (or until clicked).
    nonisolated static func popupContent(title: String, quote: String,
                                         settings: ReminderPopupSettings) -> NoticeContent {
        NoticeContent(
            title: title,
            detail: quote,
            sticky: settings.seconds == 0,
            duration: TimeInterval(max(settings.seconds, 1))
        )
    }

    // MARK: - Goal check-in

    /// True once the check-in time has passed and it hasn't shown yet today.
    nonisolated static func shouldShowGoalNudge(
        settings: GoalNudgeSettings, now: Date, calendar: Calendar = .current
    ) -> Bool {
        guard settings.isEnabled else { return false }
        guard settings.lastShownDayKey != Occurrence.dayKey(for: now, calendar: calendar) else { return false }
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour = settings.hour
        comps.minute = settings.minute
        comps.second = 0
        guard let time = calendar.date(from: comps) else { return false }
        return now >= time
    }

    /// Once a day at the check-in time (8 PM by default, set in Settings),
    /// the panel opens with each goal not answered yet today: Done or Not
    /// today. Nothing waiting: nothing shown. If nobody's looking (away /
    /// full screen) it waits and shows later, still today.
    private func checkGoalNudge(now: Date, items: [Item], occurrences: [Occurrence], held: Bool) {
        guard !showGoalCheckIn, !held,
              Self.shouldShowGoalNudge(settings: goalNudgeSettings.value, now: now),
              !GoalCheckIn.unanswered(goals: items, occurrences: occurrences, now: now).isEmpty else { return }
        goalNudgeSettings.value.lastShownDayKey = Occurrence.dayKey(for: now)
        showGoalCheckIn = true
        presenter.presentOverlay()
    }

    /// Done / Not today from the check-in. Closes it once every goal is answered.
    func answerGoal(_ goal: Item, done: Bool) {
        guard let modelContext else { return }
        let now = clock()
        GoalCheckIn.answer(goal, done: done, now: now, in: modelContext)
        let items = (try? modelContext.fetch(FetchDescriptor<Item>())) ?? []
        let occurrences = (try? modelContext.fetch(FetchDescriptor<Occurrence>())) ?? []
        if showGoalCheckIn, GoalCheckIn.unanswered(goals: items, occurrences: occurrences, now: now).isEmpty {
            dismissGoalCheckIn()
        }
    }

    func dismissGoalCheckIn() {
        guard showGoalCheckIn else { return }
        showGoalCheckIn = false
        presenter.dismissOverlay()
    }

    /// `held`: the person is away from the Mac — wait for them, without
    /// spending one of the attempts.
    private func attemptPresent(_ occurrence: Occurrence, held: Bool = false) {
        let current = clock()
        guard activeOccurrence == nil, !held, !shouldSuppress() else {
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
        if let title = occurrence.item?.title {
            DeliveryLog.record(.shown, title: title, at: clock())
        }
        activeOccurrence = occurrence
        isLiveReminderSuspended = false
        presenter.presentLiveReminder()
        // No auto-close: it stays until Done, Snooze or Skip.
    }

    /// The reminder is still on screen, unanswered, and the next escalation
    /// step is due: nag in place. The count goes up (so the face's mood steps
    /// up) and the panel comes forward. During a Focus / full screen it waits
    /// instead, without using up a step.
    private func nagInPlace(_ occurrence: Occurrence, held: Bool) {
        let current = clock()
        guard !held else {
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
        if let title = occurrence.item?.title {
            DeliveryLog.record(.unfinished, title: title, at: clock())
        }
        // Left unanswered through every nag: that's ignoring it.
        if let id = occurrence.item?.id { ignored.value.ignored(id) }
    }

    // MARK: - User actions (from the live reminder's three buttons)

    func markDone() { resolve(status: .done) }
    func skip() { resolve(status: .skipped) }
    /// Answer the reminder on screen with any status (the checklist's "Not done").
    func resolveActive(as status: OccurrenceStatus) { resolve(status: status) }

    /// From the global keyboard shortcuts: the reminder card plays its
    /// reaction and performs the action.
    func requestShortcut(_ action: ShortcutAction) {
        guard let occurrence = activeOccurrence else { return }
        // Tucked away (Focus / full screen): nothing to animate, just do it.
        guard !isLiveReminderSuspended else { perform(action); return }
        let request = ShortcutRequest(action: action)
        shortcutRequest = request
        // The card normally takes it from here. If it hasn't within a
        // couple of seconds, act directly so the key press never gets lost.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, self.shortcutRequest?.id == request.id,
                  self.activeOccurrence?.id == occurrence.id else { return }
            self.shortcutRequest = nil
            self.perform(action)
        }
    }

    /// The card picked up the shortcut and is handling it.
    func consumeShortcut() { shortcutRequest = nil }

    private func perform(_ action: ShortcutAction) {
        switch action {
        case .done: markDone()
        case .snooze: snooze()
        case .skip: skip()
        }
    }

    /// Snooze for `minutes` (the default length from Settings when nil).
    func snooze(minutes: Int? = nil) {
        guard let occurrence = activeOccurrence else { return }
        let length = max(1, minutes ?? defaultSnoozeMinutes())
        occurrence.snoozedMinutes = (occurrence.snoozedMinutes ?? 0) + length
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
        occurrence.nextEscalationAt = clock().addingTimeInterval(TimeInterval(length * 60))
        try? modelContext?.save()
        closeLiveReminder()
    }

    private func resolve(status: OccurrenceStatus) {
        guard let occurrence = activeOccurrence else { return }
        let before = OccurrenceActions.Snapshot(occurrence)
        if let title = occurrence.item?.title {
            DeliveryLog.record(.acknowledged, title: title, at: clock(),
                               detail: status == .done ? "Done" : "Skipped")
        }
        occurrence.status = status
        occurrence.resolvedAt = clock()
        occurrence.nextEscalationAt = nil
        if let id = occurrence.item?.id { ignored.value.answered(id) }
        try? modelContext?.save()
        closeLiveReminder()
        recordUndo(of: occurrence, before: before, status: status)
    }

    /// ⌘Z after Done / Skip: the reminder comes back as if never answered.
    private func recordUndo(of occurrence: Occurrence, before: OccurrenceActions.Snapshot, status: OccurrenceStatus) {
        guard status == .done || status == .skipped else { return }
        let title = occurrence.item?.title ?? "Reminder"
        undo.record((status == .done ? "Done: " : "Skipped: ") + title) { [weak self] in
            guard let self, !occurrence.isDeleted else { return }
            before.restore(occurrence)
            if occurrence.status == .pending {
                // Show it again on the next check.
                occurrence.nextEscalationAt = self.clock()
            }
            try? self.modelContext?.save()
            self.tick()
        }
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

    nonisolated static func shouldShowWeeklySummary(
        settings: WeeklySummarySettings, now: Date, calendar: Calendar = .current
    ) -> Bool {
        guard settings.isEnabled,
              calendar.component(.weekday, from: now) == settings.weekday,
              settings.lastShownWeekKey != Insights.weekKey(for: now, calendar: calendar) else { return false }
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour = settings.hour
        comps.minute = settings.minute
        comps.second = 0
        guard let time = calendar.date(from: comps) else { return false }
        return now >= time
    }

    private func checkWeeklySummary(now: Date) {
        // One overlay at a time: wait for the end-of-day summary to be closed.
        guard !showWeeklySummary, !showEndOfDaySummary, !showGoalCheckIn, !showMissed else { return }
        guard Self.shouldShowWeeklySummary(settings: weeklySettings.value, now: now) else { return }
        weeklySettings.value.lastShownWeekKey = Insights.weekKey(for: now)
        showWeeklySummary = true
        presenter.presentOverlay()
    }

    /// Opened by hand (menu bar right-click → Weekly Summary).
    func presentWeeklySummary() {
        guard !showWeeklySummary else { return }
        showWeeklySummary = true
        presenter.presentOverlay()
    }

    func dismissWeeklySummary() {
        showWeeklySummary = false
        presenter.dismissOverlay()
    }

    func dismissEndOfDaySummary() {
        showEndOfDaySummary = false
        presenter.dismissOverlay()
    }
}
