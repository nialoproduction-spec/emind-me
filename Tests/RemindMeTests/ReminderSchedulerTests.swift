import XCTest
import SwiftData
@testable import RemindMe

/// Records what the scheduler asked the screen to do, instead of showing windows.
@MainActor
final class FakePresenter: LiveReminderPresenting {
    var liveShown = 0
    var liveDismissed = 0
    var liveSuspended = 0
    var overlayShown = 0
    func presentLiveReminder() { liveShown += 1 }
    func dismissLiveReminder() { liveDismissed += 1 }
    func suspendLiveReminder() { liveSuspended += 1 }
    func presentOverlay() { overlayShown += 1 }
    func dismissOverlay() {}
}

/// The reliability-critical part: firing, nagging, snooze, sleep catch-up and
/// Focus handling, driven by a fake clock so minutes pass instantly.
@MainActor
final class ReminderSchedulerTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var presenter: FakePresenter!
    private var clock = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var suppressed = false
    private var escalation = EscalationSettings(maxReminders: 3, intervalMinutes: 15)
    private var away = false
    private var snoozeDefault = 5
    private var resumedTitles: [String] = []
    private var weekly: PersistedSettings<WeeklySummarySettings>!
    private var goalNudge: PersistedSettings<GoalNudgeSettings>!
    private var notices: [NoticeContent] = []
    private var popup: PersistedSettings<ReminderPopupSettings>!
    private var scheduler: ReminderScheduler!

    /// Fresh in-memory store + scheduler for each test (XCTest makes a new
    /// instance of this class per test, so state never leaks between them).
    private func makeFixture() throws {
        container = try ModelContainer(
            for: Item.self, Occurrence.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
        presenter = FakePresenter()
        weekly = .testing(WeeklySummarySettings(isEnabled: false))
        goalNudge = .testing(GoalNudgeSettings(isEnabled: false))
        popup = .testing(ReminderPopupSettings())
        scheduler = ReminderScheduler(
            presenter: presenter,
            now: { [unowned self] in self.clock },
            shouldSuppress: { [unowned self] in self.suppressed },
            escalationSettings: { [unowned self] in self.escalation },
            isAway: { [unowned self] in self.away },
            defaultSnoozeMinutes: { [unowned self] in self.snoozeDefault },
            resumed: { [unowned self] in self.resumedTitles.append($0.title) },
            weeklySettings: weekly,
            goalNudgeSettings: goalNudge,
            showNotice: { [unowned self] in self.notices.append($0) },
            popupSettings: popup
        )
        scheduler.attach(modelContext: context)
    }

    // MARK: - Helpers

    private func advance(minutes: Double) { clock = clock.addingTimeInterval(minutes * 60) }

    @discardableResult
    private func addRepeating(everyMinutes: Double, dueIn minutes: Double = 0, title: String = "Drink water") -> Item {
        let item = Item(title: title, kind: .repeatingRoutine, intervalSeconds: everyMinutes * 60)
        item.nextFireDate = clock.addingTimeInterval(minutes * 60)
        context.insert(item)
        return item
    }

    private func occurrences() -> [Occurrence] {
        (try? context.fetch(FetchDescriptor<Occurrence>())) ?? []
    }

    // MARK: - Reminder style / goal check-in

    func testJustRemindShowsAPopupWithNoOccurrence() throws {
        try makeFixture()
        let item = addRepeating(everyMinutes: 40, title: "Drink water")
        item.styleRaw = ReminderStyle.justRemind.rawValue
        advance(minutes: 1)
        scheduler.tick()

        XCTAssertEqual(occurrences().count, 0, "nothing to tick off")
        XCTAssertEqual(presenter.liveShown, 0, "no card with buttons")
        XCTAssertEqual(notices.map(\.title), ["Drink water"])
        XCTAssertNotNil(item.nextFireDate)
        XCTAssertGreaterThan(item.nextFireDate ?? .distantPast, clock)
    }

    func testReminderPopupStaysAsLongAsSettingsSay() throws {
        try makeFixture()
        popup.value.seconds = 20
        let item = addRepeating(everyMinutes: 40, title: "Drink water")
        item.styleRaw = ReminderStyle.justRemind.rawValue
        item.category = "Health"
        advance(minutes: 1)
        scheduler.tick()
        let shown = try XCTUnwrap(notices.last)
        XCTAssertEqual(shown.duration, 20)
        XCTAssertFalse(shown.sticky)
        let quote = try XCTUnwrap(shown.detail)
        XCTAssertTrue(ReminderQuotes.choices(for: "Drink water").contains(quote), "a water quote for a water reminder")

        let untilClicked = ReminderScheduler.popupContent(
            title: "Stretch", quote: "Motion is lotion.", settings: ReminderPopupSettings(seconds: 0))
        XCTAssertTrue(untilClicked.sticky, "0 = stays until clicked")
    }

    func testQuotesMatchTheReminder() {
        XCTAssertTrue(ReminderQuotes.choices(for: "Drink water").contains("Stay hydrated, stay sharp."))
        XCTAssertTrue(ReminderQuotes.choices(for: "Stretch my back").contains("Motion is lotion."))
        XCTAssertTrue(ReminderQuotes.choices(for: "Rest my eyes").contains("Blink. Breathe. Back to it."))
        XCTAssertTrue(ReminderQuotes.choices(for: "Renew passport").contains("Small steps, every day."),
                      "anything else gets a general one")
        XCTAssertTrue(ReminderQuotes.choices(for: "Export the Sharma teaser").contains("Back it up before it backs out."),
                      "editing work gets editing lines")
        XCTAssertGreaterThanOrEqual(ReminderQuotes.total, 200, "lots of lines")
        XCTAssertTrue(ReminderQuotes.habit.contains(ReminderQuotes.habitQuote(for: "Renew passport", pick: 3)))
        XCTAssertFalse(ReminderQuotes.goal.isEmpty)
        XCTAssertFalse(ReminderQuotes.lastWords.isEmpty)
        let allLines = ReminderQuotes.topics.flatMap(\.quotes) + ReminderQuotes.general + ReminderQuotes.habit
            + ReminderQuotes.goal + ReminderQuotes.lastWords + ReminderQuotes.ignoredWords
        XCTAssertFalse(allLines.contains { $0.contains("—") || $0.contains("–") }, "plain punctuation only")
        XCTAssertTrue(allLines.allSatisfy { $0.count <= 48 }, "short enough for one line")
    }

    func testMenuBarFaceLooksAtThePointer() {
        let right = MenuBarFace.look(dx: 200, dy: 0)
        XCTAssertEqual(right.dx, 1, accuracy: 0.001)
        let below = MenuBarFace.look(dx: 0, dy: -200) // screen y is up
        XCTAssertEqual(below.dy, 1, accuracy: 0.001, "pointer below the menu bar: pupils look down")
        let close = MenuBarFace.look(dx: 15, dy: 0)
        XCTAssertLessThan(close.dx, 0.5, "right next to it: only a small glance")
        XCTAssertEqual(MenuBarFace.look(dx: 0, dy: 0), .zero)
    }

    func testPopupSettingsFromBeforeDismissStillLoad() throws {
        let old = #"{"seconds":20}"#.data(using: .utf8)!
        let settings = try JSONDecoder().decode(ReminderPopupSettings.self, from: old)
        XCTAssertEqual(settings.seconds, 20, "the chosen time is kept")
        XCTAssertEqual(settings.dismiss, .click, "one click by default")
    }

    func testIgnoredPopupLeavesAngry() {
        XCTAssertTrue(NoticePillController.wasIgnored(idleSeconds: 0.4, pointerOnIt: false),
                      "still typing when its time ran out: ignored")
        XCTAssertFalse(NoticePillController.wasIgnored(idleSeconds: 0.4, pointerOnIt: true),
                       "pointer resting on it: reading it, not ignoring it")
        XCTAssertFalse(NoticePillController.wasIgnored(idleSeconds: 60, pointerOnIt: false),
                       "away from the Mac: it just fades")
        XCTAssertEqual(NoticePillView.mood(for: .alive), .gentle)
        XCTAssertEqual(NoticePillView.mood(for: .parting(.ignored, "Ignored again…")), .urgent, "angry")
        XCTAssertEqual(NoticePillView.mood(for: .sayonara(.ignored)), .urgent, "angry all the way out")
        XCTAssertEqual(NoticePillView.mood(for: .parting(.dismissed, "Nooooo!")), .skipped, "cries")
        XCTAssertTrue(ReminderQuotes.ignoredWords.contains("Ignored again…"))
        XCTAssertFalse(ReminderQuotes.lastWords.contains("Ignored again…"), "sent off isn't ignored")
        XCTAssertFalse(ReminderQuotes.quote(for: "Drink water", pick: -7).isEmpty, "any pick works")
    }

    func testMenuBarWatchingUsesTheOriginalFaces() {
        XCTAssertEqual(MenuBarFace.watchFace(awake: 0.2, distance: 150), .surprisedKiss, "ooh! as it wakes")
        XCTAssertEqual(MenuBarFace.watchFace(awake: 2, distance: 150), .owo, "wide awake, watching")
        XCTAssertEqual(MenuBarFace.watchFace(awake: 4.0, distance: 150), .sleepy, "a blink")
        XCTAssertEqual(MenuBarFace.watchFace(awake: 2, distance: 20), .sheepish, "shy up close")
        XCTAssertTrue(Set(MenuBarFace.watchFaces).isSubset(of: Set(Face.allCases)))
    }

    func testJustRemindIsHeldWhileFocusIsOn() throws {
        try makeFixture()
        let item = addRepeating(everyMinutes: 40)
        item.styleRaw = ReminderStyle.justRemind.rawValue
        suppressed = true
        advance(minutes: 1)
        scheduler.tick()
        XCTAssertTrue(notices.isEmpty)
        XCTAssertGreaterThan(item.nextFireDate ?? .distantPast, clock, "still moves on")
    }

    func testGoalNudgeTimingAndOncePerDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let day = cal.date(from: DateComponents(year: 2026, month: 3, day: 3, hour: 19, minute: 59))!
        let eight = cal.date(from: DateComponents(year: 2026, month: 3, day: 3, hour: 20, minute: 0))!
        var settings = GoalNudgeSettings()
        XCTAssertFalse(ReminderScheduler.shouldShowGoalNudge(settings: settings, now: day, calendar: cal))
        XCTAssertTrue(ReminderScheduler.shouldShowGoalNudge(settings: settings, now: eight, calendar: cal))
        settings.lastShownDayKey = Occurrence.dayKey(for: eight, calendar: cal)
        XCTAssertFalse(ReminderScheduler.shouldShowGoalNudge(settings: settings, now: eight, calendar: cal))
        settings.lastShownDayKey = nil
        settings.isEnabled = false
        XCTAssertFalse(ReminderScheduler.shouldShowGoalNudge(settings: settings, now: eight, calendar: cal))
    }

    func testTypeChooserMapping() {
        var parsed = ItemParser.parse("Drink water every 40 minutes")
        XCTAssertEqual(parsed.type, .reminder)
        parsed.chosen = .habit
        XCTAssertEqual(parsed.type, .habit)
        parsed.chosen = .goal
        XCTAssertEqual(parsed.type, .goal)

        var plain = ItemParser.parse("Go to Godavari")
        XCTAssertEqual(plain.type, .goal)
        plain.chosen = .habit
        XCTAssertEqual(plain.type, .goal, "no schedule, so it can't be a habit")

        var habit = ItemParser.parse("Stretch every 2 hours")
        habit.chosen = .habit
        XCTAssertEqual(Item(from: habit).style, .habit)
        habit.chosen = .reminder
        XCTAssertEqual(Item(from: habit).style, .justRemind)
        habit.chosen = .goal
        XCTAssertEqual(Item(from: habit).kind, .goal)
    }

    // MARK: - Smarter typing

    func testRemindMeToIsDropped() {
        let p = ItemParser.parse("remind me to drink water every 4 minute")
        XCTAssertEqual(p.title, "Drink water")
        XCTAssertEqual(p.intervalSeconds, 240)
        XCTAssertEqual(p.type, .reminder, "a time → just a reminder, no clicking")
        XCTAssertEqual(ItemParser.parse("Reminder: stretch every hour").title, "Stretch")
        XCTAssertEqual(ItemParser.parse("don't forget to call mom at 5pm").title, "Call mom")
        XCTAssertEqual(ItemParser.parse("remind me").title, "Remind me", "nothing after it: kept as typed")
    }

    func testTyposInEveryAndUnits() {
        XCTAssertEqual(ItemParser.parse("drink water rvry 4 minute").intervalSeconds, 240)
        XCTAssertEqual(ItemParser.parse("drink water rvrry 4 minute").title, "Drink water")
        XCTAssertEqual(ItemParser.parse("drink water evry 4 minuts").intervalSeconds, 240)
        XCTAssertEqual(ItemParser.parse("stretch evrey 2 houres").intervalSeconds, 7200)
        XCTAssertEqual(ItemParser.parse("sleep over 2 hours").kind, .goal, "real words aren't 'fixed'")
        XCTAssertEqual(ItemParser.editDistance("rvry", "every"), 2)
    }

    func testNoTimeIsAGoalAutomatically() {
        let p = ItemParser.parse("finish the Sharma wedding edit")
        XCTAssertEqual(p.type, .goal)
        XCTAssertFalse(p.hasSchedule, "so the Habit button is off")
    }

    // MARK: - Goal check-in

    private func turnOnGoalCheckIn() {
        goalNudge.value = GoalNudgeSettings(isEnabled: true, hour: 0, minute: 0)
    }

    private func addGoal(_ title: String = "Edit 2 hours") -> Item {
        let goal = Item(title: title, kind: .goal)
        context.insert(goal)
        return goal
    }

    func testCheckInOpensWithOpenGoalsOncePerDay() throws {
        try makeFixture()
        turnOnGoalCheckIn()
        _ = addGoal()
        scheduler.tick()
        XCTAssertTrue(scheduler.showGoalCheckIn)
        XCTAssertEqual(presenter.overlayShown, 1)

        scheduler.dismissGoalCheckIn() // Later
        scheduler.tick()
        XCTAssertFalse(scheduler.showGoalCheckIn, "Later means tomorrow")
        XCTAssertEqual(presenter.overlayShown, 1)
    }

    func testNoGoalsNoCheckIn() throws {
        try makeFixture()
        turnOnGoalCheckIn()
        let done = addGoal()
        done.isAchieved = true
        scheduler.tick()
        XCTAssertFalse(scheduler.showGoalCheckIn)
    }

    func testDoneAndNotTodayAreRecordedAndCloseTheCheckIn() throws {
        try makeFixture()
        turnOnGoalCheckIn()
        let edit = addGoal("Edit 2 hours")
        let gym = addGoal("Gym")
        scheduler.tick()
        XCTAssertTrue(scheduler.showGoalCheckIn)

        scheduler.answerGoal(edit, done: true)
        XCTAssertTrue(scheduler.showGoalCheckIn, "one still waiting")
        scheduler.answerGoal(gym, done: false)
        XCTAssertFalse(scheduler.showGoalCheckIn, "all answered: it closes")

        let answers = occurrences()
        XCTAssertEqual(answers.count, 2)
        XCTAssertEqual(answers.first { $0.item?.title == "Edit 2 hours" }?.status, .done)
        XCTAssertEqual(answers.first { $0.item?.title == "Gym" }?.status, .skipped, "Not today")
        XCTAssertTrue(answers.allSatisfy { $0.nextEscalationAt == nil }, "answers never nag")

        // Changing your mind the same day replaces the answer.
        scheduler.answerGoal(gym, done: true)
        XCTAssertEqual(occurrences().count, 2)
        XCTAssertEqual(GoalCheckIn.todaysAnswer(for: gym, in: occurrences(), now: clock)?.status, .done)
        XCTAssertTrue(GoalCheckIn.unanswered(goals: [edit, gym], occurrences: occurrences(), now: clock).isEmpty)
    }

    func testGoalAnswersMakeAStreak() throws {
        try makeFixture()
        let goal = addGoal()
        for day in 0..<3 {
            GoalCheckIn.answer(goal, done: true, now: clock.addingTimeInterval(Double(-day) * 86400), in: context)
        }
        let mine = Insights.occurrences(of: goal, in: occurrences())
        XCTAssertEqual(mine.filter { $0.status == .done }.count, 3, "3 total")
        XCTAssertEqual(Insights.streak(Insights.dailyRecords(mine, days: 60, now: clock)), 3, "3 days in a row")
    }

    func testGoalAnswersDontPopAnything() throws {
        try makeFixture()
        let goal = addGoal()
        GoalCheckIn.answer(goal, done: false, now: clock, in: context)
        advance(minutes: 30)
        scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 0)
        XCTAssertNil(scheduler.activeOccurrence)
    }

    func testSnoozeChoicesDefaultTo5_10_30() {
        XCTAssertEqual(SnoozeSettings().presets, [5, 10, 30])
    }

    func testIslandSitsOnTheNotch() {
        // 16-inch MacBook Pro at its default size.
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let notch = IslandGeometry.notch(CGSize(width: 200, height: 37))
        XCTAssertTrue(notch.hasNotch)
        let frame = IslandGeometry.frame(screen: screen, notch: notch, left: 45, right: 60)
        XCTAssertEqual(frame.height, 37, "as tall as the notch")
        XCTAssertEqual(frame.maxY, 1117, "flush with the top of the screen")
        XCTAssertEqual(frame.minX, 864 - 100 - 45, "left side starts 45 pt out from the notch")
        XCTAssertEqual(frame.maxX, 864 + 100 + 60, "right side ends 60 pt out from the notch")

        let plain = IslandGeometry.notch(.zero)
        XCTAssertFalse(plain.hasNotch)
        XCTAssertEqual(plain.middleWidth, IslandGeometry.noNotchGap)
    }

    func testIslandSidesFitTheirOwnContent() {
        XCTAssertEqual(IslandGeometry.side(30), 30 + IslandGeometry.innerGap + IslandGeometry.outerPadding)
        XCTAssertEqual(IslandGeometry.side(5), IslandGeometry.minWing, "never too thin")
        XCTAssertEqual(IslandGeometry.side(900), IslandGeometry.maxWing, "never too far out")
    }

    @MainActor
    func testCompactIslandIsSmall() {
        let now = Date()
        let compact = BreakIslandController.sides(for: NoticeContent(
            title: "", countdownTo: now.addingTimeInterval(38 * 60), face: .smug, tone: .work))
        XCTAssertLessThanOrEqual(compact.left, 50, "just the face")
        XCTAssertLessThanOrEqual(compact.right, 70, "just the time")
        let state = BreakCycleState.started(BreakCycleConfig(workMinutes: 40, breakMinutes: 10), at: now)
        XCTAssertTrue(BreakIslandRules.content(for: state).title.isEmpty, "between moments: no words")
    }

    func testShortcutUnitsInIntervals() {
        XCTAssertEqual(ItemParser.parse("drink water every 40m").intervalSeconds, 2400)
        XCTAssertEqual(ItemParser.parse("stretch every 2 hrs").intervalSeconds, 7200)
        XCTAssertEqual(ItemParser.parse("stretch every 2h").intervalSeconds, 7200)
        XCTAssertEqual(ItemParser.parse("blink every 30 sec").intervalSeconds, 30)
        XCTAssertEqual(ItemParser.parse("blink every 30s").intervalSeconds, 30)
        XCTAssertEqual(ItemParser.parse("drink water every 4 mins").intervalSeconds, 240)
        XCTAssertEqual(ItemParser.parse("drink water every 40m").title, "Drink water")
        XCTAssertEqual(ItemParser.parse("call mom every morning").kind, .goal, "no unit, no interval")
    }

    // MARK: - Firing

    func testDueRoutinePopsTheReminder() throws {
        try makeFixture()
        let item = addRepeating(everyMinutes: 40)
        advance(minutes: 1)
        scheduler.tick()

        XCTAssertEqual(occurrences().count, 1)
        XCTAssertEqual(occurrences().first?.status, .pending)
        XCTAssertEqual(occurrences().first?.remindersSentCount, 1)
        XCTAssertEqual(presenter.liveShown, 1)
        XCTAssertNotNil(scheduler.activeOccurrence)
        // Next one is scheduled from the due time, as an absolute timestamp.
        XCTAssertEqual(item.nextFireDate, clock.addingTimeInterval(-60 + 40 * 60))
    }

    func testNotDueYetDoesNothing() throws {
        try makeFixture()
        addRepeating(everyMinutes: 40, dueIn: 10)
        advance(minutes: 5)
        scheduler.tick()
        XCTAssertEqual(occurrences().count, 0)
        XCTAssertEqual(presenter.liveShown, 0)
    }

    func testGoalsAndPausedRoutinesNeverPop() throws {
        try makeFixture()
        context.insert(Item(title: "Go to Godavari", kind: .goal))
        let paused = addRepeating(everyMinutes: 1)
        paused.isActive = false
        advance(minutes: 10)
        scheduler.tick()
        XCTAssertEqual(occurrences().count, 0)
        XCTAssertEqual(presenter.liveShown, 0)
    }

    // MARK: - Stays until answered

    func testReminderStaysOnScreenUntilAnswered() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)
        scheduler.tick()
        for _ in 0..<24 { advance(minutes: 5); scheduler.tick() } // two hours, nobody answers
        XCTAssertNotNil(scheduler.activeOccurrence, "never closes on its own")
        XCTAssertEqual(presenter.liveDismissed, 0)
    }

    func testUnansweredReminderNagsInPlaceThenCountsAsUnfinished() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)       // long interval so only one occurrence is in play
        scheduler.tick()                      // shown (1)
        let shown = scheduler.activeOccurrence

        advance(minutes: 14); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 1, "no nag before 15 minutes")

        advance(minutes: 1.1); scheduler.tick() // nag 2 at 15m
        advance(minutes: 15.1); scheduler.tick() // nag 3 at 30m
        XCTAssertEqual(presenter.liveShown, 3)
        XCTAssertEqual(occurrences().first?.remindersSentCount, 3)

        advance(minutes: 15.1); scheduler.tick() // 45m: out of nags
        XCTAssertEqual(occurrences().first?.status, .unfinished, "counts as unfinished for the day")
        XCTAssertEqual(scheduler.activeOccurrence?.id, shown?.id, "but stays on screen to be answered")
        XCTAssertEqual(presenter.liveDismissed, 0)

        advance(minutes: 60); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 3, "and stops nagging")
    }

    func testMoodRisesWithEachNag() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)
        func mood() -> FaceMood {
            FaceMood.forPop(count: scheduler.activeOccurrence!.remindersSentCount, maxPops: escalation.maxReminders)
        }
        scheduler.tick()
        XCTAssertEqual(mood(), .gentle)
        advance(minutes: 15.1); scheduler.tick()
        XCTAssertEqual(mood(), .nudge)
        advance(minutes: 15.1); scheduler.tick()
        XCTAssertEqual(mood(), .urgent)
    }

    func testCustomEscalationSettingsAreRespected() throws {
        try makeFixture()
        escalation = EscalationSettings(maxReminders: 2, intervalMinutes: 5)
        addRepeating(everyMinutes: 600)
        scheduler.tick()                         // 1
        advance(minutes: 5.1); scheduler.tick()  // 2
        advance(minutes: 5.1); scheduler.tick()  // out of nags
        XCTAssertEqual(presenter.liveShown, 2)
        XCTAssertEqual(occurrences().first?.status, .unfinished)
    }

    // MARK: - The three buttons

    func testDoneClosesItAndStopsTheNagging() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)
        scheduler.tick()
        scheduler.markDone()
        XCTAssertEqual(occurrences().first?.status, .done)
        XCTAssertNil(scheduler.activeOccurrence)
        XCTAssertEqual(presenter.liveDismissed, 1)
        advance(minutes: 30); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 1)
    }

    func testSkipClosesItAndStopsTheNagging() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)
        scheduler.tick()
        scheduler.skip()
        XCTAssertEqual(occurrences().first?.status, .skipped)
        XCTAssertEqual(presenter.liveDismissed, 1)
        advance(minutes: 30); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 1)
    }

    func testSnoozeComesBackInFiveMinutes() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)
        scheduler.tick()
        scheduler.snooze()
        XCTAssertNil(scheduler.activeOccurrence)
        advance(minutes: 4.9); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 1, "not before 5 minutes")
        advance(minutes: 0.2); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 2, "back after 5 minutes")
    }

    func testSnoozeOnTheLastNagStillComesBack() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)
        scheduler.tick()                          // 1
        advance(minutes: 15.1); scheduler.tick()  // 2
        advance(minutes: 15.1); scheduler.tick()  // 3 (last)
        scheduler.snooze()

        advance(minutes: 5.1); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 4, "a snooze must always come back")
        XCTAssertEqual(occurrences().first?.status, .pending)
    }

    func testAnsweringAfterItWentUnfinishedStillWorks() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)
        scheduler.tick()
        advance(minutes: 15.1); scheduler.tick()
        advance(minutes: 15.1); scheduler.tick()
        advance(minutes: 15.1); scheduler.tick()
        XCTAssertEqual(occurrences().first?.status, .unfinished)

        scheduler.markDone()
        XCTAssertEqual(occurrences().first?.status, .done, "late Done still counts")
        XCTAssertNil(scheduler.activeOccurrence)
    }

    func testSnoozingAnUnfinishedReminderPutsItBackInPlay() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)
        scheduler.tick()
        advance(minutes: 15.1); scheduler.tick()
        advance(minutes: 15.1); scheduler.tick()
        advance(minutes: 15.1); scheduler.tick()
        scheduler.snooze()
        XCTAssertEqual(occurrences().first?.status, .pending)
        advance(minutes: 5.1); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 4)
    }

    // MARK: - Sleep / wake

    func testLongSleepFiresOnceNotABacklog() throws {
        try makeFixture()
        let item = addRepeating(everyMinutes: 40)
        advance(minutes: 5 * 60)               // Mac asleep for 5 hours
        scheduler.tick()                       // what the wake notification triggers
        XCTAssertEqual(occurrences().count, 1, "one catch-up, not 7 stacked reminders")
        XCTAssertEqual(presenter.liveShown, 1)
        XCTAssertEqual(item.nextFireDate, clock.addingTimeInterval(40 * 60),
                       "next one counts from now, not from before the sleep")
    }

    // MARK: - Focus / full screen

    func testSuppressedDoesNotUseUpAnAttempt() throws {
        try makeFixture()
        suppressed = true
        addRepeating(everyMinutes: 600)
        scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 0, "nothing pops during Do Not Disturb / full screen")
        XCTAssertEqual(occurrences().first?.remindersSentCount, 0)

        suppressed = false
        advance(minutes: 1); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 1, "shows once the Focus ends")
        XCTAssertEqual(occurrences().first?.remindersSentCount, 1)
    }

    func testWaitingReminderTucksAwayDuringFocusAndComesBack() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)
        scheduler.tick()                                   // on screen

        suppressed = true
        scheduler.tick()
        XCTAssertEqual(presenter.liveSuspended, 1, "hidden while the Focus is on")
        XCTAssertTrue(scheduler.isLiveReminderSuspended)
        XCTAssertNotNil(scheduler.activeOccurrence, "hidden, not dropped")

        advance(minutes: 15.1); scheduler.tick()
        XCTAssertEqual(occurrences().first?.remindersSentCount, 1, "no nag spent during the Focus")

        suppressed = false
        scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 2, "back when the Focus ends")
        XCTAssertFalse(scheduler.isLiveReminderSuspended)

        advance(minutes: 1); scheduler.tick()
        XCTAssertEqual(occurrences().first?.remindersSentCount, 2, "then the delayed nag happens")
    }

    // MARK: - More than one due

    func testTwoDueAtOnceShowOneAtATime() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)
        addRepeating(everyMinutes: 600, title: "Stretch")

        scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 1, "never two reminders on screen at once")
        scheduler.markDone()
        advance(minutes: 1); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 2, "the second one gets its turn")
    }

    func testNextReminderWaitsWhileOneIsUnanswered() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600, title: "Drink water")
        addRepeating(everyMinutes: 600, dueIn: 10, title: "Stretch")
        scheduler.tick()
        let first = scheduler.activeOccurrence
        for _ in 0..<8 { advance(minutes: 5); scheduler.tick() }
        XCTAssertEqual(scheduler.activeOccurrence?.id, first?.id, "Stretch waits its turn")

        scheduler.markDone()
        advance(minutes: 1); scheduler.tick()
        XCTAssertEqual(scheduler.activeOccurrence?.item?.title, "Stretch")
    }

    // MARK: - Snooze lengths

    func testSnoozeForAChosenLength() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)
        scheduler.tick()
        scheduler.snooze(minutes: 30)
        XCTAssertEqual(occurrences().first?.snoozedMinutes, 30)
        advance(minutes: 29); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 1, "not before 30 minutes")
        advance(minutes: 1.1); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 2)

        scheduler.snooze(minutes: 15)
        XCTAssertEqual(occurrences().first?.snoozedMinutes, 45, "snoozes add up")
    }

    func testPlainSnoozeUsesTheDefaultLength() throws {
        try makeFixture()
        snoozeDefault = 15
        addRepeating(everyMinutes: 600)
        scheduler.tick()
        scheduler.snooze()
        advance(minutes: 14); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 1)
        advance(minutes: 1.1); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 2)
    }

    // MARK: - Pause for a while

    func testTimedPauseResumesByItself() throws {
        try makeFixture()
        let item = addRepeating(everyMinutes: 40)
        ItemActions.pause(item, until: clock.addingTimeInterval(3600), in: context,
                          scheduler: scheduler, cancelNotifications: { _ in })
        XCTAssertFalse(item.isActive)
        XCTAssertNil(item.nextFireDate)

        advance(minutes: 59); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 0, "quiet while paused")
        XCTAssertFalse(item.isActive)

        advance(minutes: 1.5); scheduler.tick()
        XCTAssertTrue(item.isActive, "back on after the hour")
        XCTAssertNil(item.pausedUntil)
        XCTAssertEqual(resumedTitles, ["Drink water"], "notifications re-scheduled")
        XCTAssertEqual(item.nextFireDate, clock.addingTimeInterval(40 * 60), "next one counted from the resume")
    }

    func testPauseWithNoEndStaysPaused() throws {
        try makeFixture()
        let item = addRepeating(everyMinutes: 40)
        ItemActions.pause(item, until: nil, in: context, scheduler: scheduler, cancelNotifications: { _ in })
        advance(minutes: 60 * 24 * 3); scheduler.tick()
        XCTAssertFalse(item.isActive)
        XCTAssertEqual(presenter.liveShown, 0)
    }

    func testPausingTheRoutineOnScreenClosesIt() throws {
        try makeFixture()
        let item = addRepeating(everyMinutes: 40)
        scheduler.tick()
        XCTAssertNotNil(scheduler.activeOccurrence)
        ItemActions.pause(item, until: nil, in: context, scheduler: scheduler, cancelNotifications: { _ in })
        XCTAssertNil(scheduler.activeOccurrence)
        XCTAssertEqual(presenter.liveDismissed, 1)
        XCTAssertEqual(occurrences().first?.status, .skipped)
    }

    func testPausingSetsAsideASnoozedReminder() throws {
        try makeFixture()
        let item = addRepeating(everyMinutes: 600)
        scheduler.tick()
        scheduler.snooze(minutes: 5)
        ItemActions.pause(item, until: clock.addingTimeInterval(600), in: context,
                          scheduler: scheduler, cancelNotifications: { _ in })
        advance(minutes: 6); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 1, "the snoozed one doesn't come back during the pause")
        XCTAssertEqual(occurrences().first?.status, .skipped)
    }

    // MARK: - Away from the Mac

    func testRemindersWaitWhileAwayWithoutUsingAttempts() throws {
        try makeFixture()
        away = true
        addRepeating(everyMinutes: 600)
        scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 0, "held while nobody's there")
        XCTAssertEqual(occurrences().first?.remindersSentCount, 0)

        advance(minutes: 30); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 0)

        away = false
        advance(minutes: 1); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 1, "shown on return")
        XCTAssertEqual(occurrences().first?.remindersSentCount, 1, "first pop, not a nag")
    }

    func testOnScreenReminderDoesNotNagAnEmptyRoom() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)
        scheduler.tick()
        away = true
        advance(minutes: 15.1); scheduler.tick()
        advance(minutes: 15.1); scheduler.tick()
        XCTAssertEqual(occurrences().first?.remindersSentCount, 1)
        XCTAssertEqual(occurrences().first?.status, .pending, "not run out while away")

        away = false
        advance(minutes: 1); scheduler.tick()
        XCTAssertEqual(occurrences().first?.remindersSentCount, 2, "nags resume when back")
    }

    // MARK: - Weekly summary

    func testWeeklySummaryShowsOncePerWeek() throws {
        try makeFixture()
        let calendar = Calendar.current
        var settings = WeeklySummarySettings(isEnabled: true)
        settings.weekday = calendar.component(.weekday, from: clock)
        let minutes = calendar.component(.hour, from: clock) * 60 + calendar.component(.minute, from: clock)
        let at = max(0, minutes - 1)
        settings.hour = at / 60
        settings.minute = at % 60
        weekly.value = settings

        scheduler.tick()
        XCTAssertTrue(scheduler.showWeeklySummary)
        XCTAssertEqual(weekly.value.lastShownWeekKey, Insights.weekKey(for: clock))

        scheduler.dismissWeeklySummary()
        advance(minutes: 30); scheduler.tick()
        XCTAssertFalse(scheduler.showWeeklySummary, "only once that week")
    }

    func testWeeklySummaryTimingRules() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // Sunday 2026-10-11, 18:59 and 19:00 UTC.
        let before = calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 18, minute: 59))!
        let at = calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 19))!
        var settings = WeeklySummarySettings(isEnabled: true, weekday: 1, hour: 19, minute: 0)
        XCTAssertFalse(ReminderScheduler.shouldShowWeeklySummary(settings: settings, now: before, calendar: calendar))
        XCTAssertTrue(ReminderScheduler.shouldShowWeeklySummary(settings: settings, now: at, calendar: calendar))
        let monday = calendar.date(byAdding: .day, value: 1, to: at)!
        XCTAssertFalse(ReminderScheduler.shouldShowWeeklySummary(settings: settings, now: monday, calendar: calendar),
                       "only on the chosen day")
        settings.lastShownWeekKey = Insights.weekKey(for: at, calendar: calendar)
        XCTAssertFalse(ReminderScheduler.shouldShowWeeklySummary(settings: settings, now: at, calendar: calendar))
        settings.isEnabled = false
        settings.lastShownWeekKey = nil
        XCTAssertFalse(ReminderScheduler.shouldShowWeeklySummary(settings: settings, now: at, calendar: calendar))
    }

    // MARK: - Keyboard shortcuts

    func testShortcutIsHandedToTheCard() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)
        scheduler.tick()
        scheduler.requestShortcut(.done)
        XCTAssertEqual(scheduler.shortcutRequest?.action, .done)
        scheduler.consumeShortcut()
        XCTAssertNil(scheduler.shortcutRequest)
    }

    func testShortcutWithNothingOnScreenDoesNothing() throws {
        try makeFixture()
        scheduler.requestShortcut(.skip)
        XCTAssertNil(scheduler.shortcutRequest)
    }

    func testShortcutWhileTuckedAwayActsDirectly() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)
        scheduler.tick()
        suppressed = true
        scheduler.tick()
        XCTAssertTrue(scheduler.isLiveReminderSuspended)
        scheduler.requestShortcut(.done)
        XCTAssertEqual(occurrences().first?.status, .done)
        XCTAssertNil(scheduler.activeOccurrence)
    }

    func testUnhandledShortcutStillActs() async throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)
        scheduler.tick()
        scheduler.requestShortcut(.skip)
        try await Task.sleep(for: .milliseconds(2300))
        XCTAssertEqual(occurrences().first?.status, .skipped, "never lost, even if the card didn't pick it up")
    }

    // MARK: - Checklist

    func testTickingOffTheReminderOnScreenAnswersIt() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)
        scheduler.tick()
        let occurrence = try XCTUnwrap(occurrences().first)
        OccurrenceActions.toggle(occurrence, now: clock, scheduler: scheduler)
        XCTAssertEqual(occurrence.status, .done)
        XCTAssertNil(scheduler.activeOccurrence)
        XCTAssertEqual(presenter.liveDismissed, 1)
    }

    func testUntickingDoesNotHoldUpTheNextReminder() throws {
        try makeFixture()
        let item = addRepeating(everyMinutes: 60)
        scheduler.tick()
        scheduler.markDone()
        let occurrence = try XCTUnwrap(occurrences().first)
        OccurrenceActions.toggle(occurrence, now: clock, scheduler: scheduler)
        XCTAssertEqual(occurrence.status, .unfinished, "not done = missed")
        XCTAssertNil(occurrence.nextEscalationAt)

        advance(minutes: 61); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 2, "the routine carries on")
        XCTAssertNotNil(item.nextFireDate)
    }
}
