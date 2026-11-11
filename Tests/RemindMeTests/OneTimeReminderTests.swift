import XCTest
import SwiftData
@testable import RemindMe

/// A timed reminder repeats ONLY when the text says so. "drink water at
/// 10 am" and "12 pm read book" go off once and are then over.
@MainActor
final class OneTimeReminderTests: XCTestCase {

    private var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kathmandu")!
        return cal
    }()

    /// Wednesday 11 November 2026, 09:00.
    private var now: Date { date(11, 9) }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func parse(_ text: String) -> ParsedItem {
        ItemParser.parse(text, now: now, calendar: calendar)
    }

    // MARK: - Parser: one-time by default

    func testAtTimeWithoutEveryIsOneTime() {
        let p = parse("remind me to drink water at 10 AM")
        XCTAssertEqual(p.kind, .scheduledRoutine)
        XCTAssertEqual(p.onceAt, date(11, 10))
        XCTAssertTrue(p.weekdays.isEmpty)
        XCTAssertEqual(p.title, "Drink water")
        XCTAssertTrue(p.detailLine.hasPrefix("Once"), p.detailLine)
    }

    func testTimeWithoutAtIsUnderstood() {
        let p = parse("12 pm READ BOOK")
        XCTAssertEqual(p.kind, .scheduledRoutine)
        XCTAssertEqual(p.hour, 12)
        XCTAssertEqual(p.minute, 0)
        XCTAssertEqual(p.onceAt, date(11, 12))
        XCTAssertEqual(p.title, "READ BOOK")
    }

    func testBareTimeWithMinutes() {
        let p = parse("call mom 4:30pm")
        XCTAssertEqual(p.hour, 16)
        XCTAssertEqual(p.minute, 30)
        XCTAssertEqual(p.onceAt, date(11, 16, 30))
        XCTAssertEqual(p.title, "Call mom")
    }

    func testTimeAlreadyPassedTodayMeansTomorrow() {
        XCTAssertEqual(parse("drink water at 8 AM").onceAt, date(12, 8))
    }

    func testTomorrowAndTonight() {
        let tomorrow = parse("call mom tomorrow at 5pm")
        XCTAssertEqual(tomorrow.onceAt, date(12, 17))
        XCTAssertEqual(tomorrow.title, "Call mom")

        let tonight = parse("call dad tonight at 9")
        XCTAssertEqual(tonight.onceAt, date(11, 21), "tonight at 9 is 9 PM")
        XCTAssertEqual(tonight.title, "Call dad")
    }

    func testInTenMinutes() {
        let p = parse("stretch in 10 minutes")
        XCTAssertEqual(p.kind, .scheduledRoutine)
        XCTAssertEqual(p.onceAt, date(11, 9, 10))
        XCTAssertEqual(p.title, "Stretch")
    }

    func testInAnHour() {
        XCTAssertEqual(parse("take a break in an hour").onceAt, date(11, 10))
        XCTAssertEqual(parse("laundry in half an hour").onceAt, date(11, 9, 30))
    }

    func testOneNamedDayIsOneTime() {
        // Wed 11 Nov -> next Monday is 16 Nov.
        let p = parse("gym at 6pm on monday")
        XCTAssertEqual(p.onceAt, date(16, 18))
        XCTAssertTrue(p.weekdays.isEmpty)
    }

    // MARK: - Parser: repeats only when asked

    func testEveryDayRepeats() {
        XCTAssertNil(parse("meditate every day at 6am").onceAt)
        XCTAssertNil(parse("meditate daily at 6am").onceAt)
        XCTAssertNil(parse("meditate everyday 6am").onceAt)
        XCTAssertNil(parse("call mom every 6pm").onceAt)
        XCTAssertEqual(parse("meditate daily at 6am").kind, .scheduledRoutine)
    }

    func testEveryMondayRepeatsOnThatDay() {
        let p = parse("gym every monday at 6pm")
        XCTAssertNil(p.onceAt)
        XCTAssertEqual(p.weekdays, [2])
        XCTAssertEqual(p.title, "Gym")
    }

    func testPluralDaysAndWeekdaysRepeat() {
        XCTAssertNil(parse("gym at 6pm mondays").onceAt)
        XCTAssertEqual(parse("gym at 6pm tuesdays").weekdays, [3], "plural tuesdays")
        XCTAssertEqual(parse("gym at 6pm thursdays").weekdays, [5], "plural thursdays")
        XCTAssertNil(parse("standup at 10am weekdays").onceAt)
        XCTAssertNil(parse("gym at 6pm monday and wednesday").onceAt)
    }

    func testWeeklyRepeatsOnTodaysWeekday() {
        let p = parse("review notes at 5pm every week")
        XCTAssertNil(p.onceAt)
        XCTAssertEqual(p.weekdays, [4]) // Wednesday
        XCTAssertEqual(p.title, "Review notes")
    }

    func testRulesRepeat() {
        XCTAssertNil(parse("take pills every morning").onceAt)
        XCTAssertNil(parse("take pills twice a day").onceAt)
        XCTAssertNil(parse("take pills at 9am for 7 days").onceAt)
        XCTAssertNil(parse("take pills at 9am and 9pm").onceAt)
        XCTAssertNil(parse("water plants every other day at 7am").onceAt)
        XCTAssertNotNil(parse("take pills at night").onceAt, "no repeat word: tonight, once")
    }

    func testEveryOneMinuteStillRepeats() {
        let p = parse("drink water every 1 min")
        XCTAssertEqual(p.kind, .repeatingRoutine)
        XCTAssertEqual(p.intervalSeconds, 60)
        XCTAssertNil(p.onceAt)
    }

    func testLogInIsNotAStopword() {
        XCTAssertEqual(parse("log in at 9pm").title, "Log in")
    }

    // MARK: - Item

    private func oneTimeItem(at fire: Date) -> Item {
        let item = Item(title: "Read book", kind: .scheduledRoutine, hour: 12, minute: 0)
        item.onceAt = fire
        item.nextFireDate = fire
        return item
    }

    func testOneTimeNextFireIsItsMomentThenNothing() {
        let item = oneTimeItem(at: date(11, 12))
        XCTAssertEqual(item.computeNextFireDate(after: now, calendar: calendar), date(11, 12))
        XCTAssertNil(item.computeNextFireDate(after: date(11, 12), calendar: calendar), "must not roll to tomorrow")
        XCTAssertNil(item.computeNextFireDate(after: date(15, 8), calendar: calendar))
    }

    func testResumeNeverRevivesAPassedOneTime() {
        let item = oneTimeItem(at: date(11, 12))
        item.isActive = false
        item.arm(after: date(11, 15), calendar: calendar)
        XCTAssertNil(item.nextFireDate)
        XCTAssertFalse(item.isActive)
        XCTAssertTrue(item.isOver)
    }

    func testNextClockTime() {
        XCTAssertEqual(Item.nextClockTime(hour: 10, minute: 0, after: now, calendar: calendar), date(11, 10))
        XCTAssertEqual(Item.nextClockTime(hour: 8, minute: 0, after: now, calendar: calendar), date(12, 8))
        XCTAssertEqual(Item.nextClockTime(hour: 9, minute: 0, after: now, calendar: calendar), date(12, 9))
    }

    // MARK: - Editing

    func testEditingADailyIntoOneTimeAndBack() {
        let item = Item(title: "Walk", kind: .scheduledRoutine, hour: 9, minute: 0)
        item.nextFireDate = item.computeNextFireDate(after: now, calendar: calendar)
        var edit = ItemActions.Edit(of: item)
        XCTAssertTrue(edit.repeats)

        edit.repeats = false
        edit.hour = 10
        edit.minute = 30
        ItemActions.apply(edit, to: item, now: now, reschedule: { _ in })
        XCTAssertNotNil(item.onceAt)
        XCTAssertEqual(item.nextFireDate, item.onceAt)
        XCTAssertNil(item.weekdaysRaw)

        var back = ItemActions.Edit(of: item)
        XCTAssertFalse(back.repeats)
        back.repeats = true
        ItemActions.apply(back, to: item, now: now, reschedule: { _ in })
        XCTAssertNil(item.onceAt)
        XCTAssertNotNil(item.nextFireDate)
    }

    func testEditingAFinishedOneTimeBringsItBack() {
        let item = oneTimeItem(at: date(11, 8))
        item.endedAt = date(11, 8)
        item.nextFireDate = nil
        var edit = ItemActions.Edit(of: item)
        edit.hour = 18
        edit.minute = 0
        ItemActions.apply(edit, to: item, now: now, reschedule: { _ in })
        XCTAssertFalse(item.isOver)
        XCTAssertTrue(item.isActive)
        XCTAssertNotNil(item.nextFireDate)
    }

    // MARK: - Scheduler: fires once, never again

    private var container: ModelContainer!
    private var context: ModelContext!
    private var presenter: FakePresenter!
    private var clock = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var scheduler: ReminderScheduler!

    private func makeFixture() throws {
        container = try ModelContainer(
            for: Item.self, Occurrence.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
        presenter = FakePresenter()
        scheduler = ReminderScheduler(
            presenter: presenter,
            now: { [unowned self] in self.clock },
            shouldSuppress: { false },
            escalationSettings: { EscalationSettings(maxReminders: 3, intervalMinutes: 15) },
            isAway: { false },
            defaultSnoozeMinutes: { 5 },
            resumed: { _ in },
            weeklySettings: .testing(WeeklySummarySettings(isEnabled: false)),
            goalNudgeSettings: .testing(GoalNudgeSettings(isEnabled: false)),
            showNotice: { _ in },
            popupSettings: .testing(ReminderPopupSettings()),
            missed: .testing(MissedList()),
            ignored: .testing(IgnoreCounts()),
            undo: UndoCenter()
        )
        scheduler.attach(modelContext: context)
    }

    private func occurrences() -> [Occurrence] {
        (try? context.fetch(FetchDescriptor<Occurrence>())) ?? []
    }

    private func addOneTimeHabit(dueIn seconds: TimeInterval) -> Item {
        let item = Item(title: "Drink water", kind: .scheduledRoutine, hour: 10, minute: 0, style: .habit)
        item.onceAt = clock.addingTimeInterval(seconds)
        item.nextFireDate = item.onceAt
        context.insert(item)
        return item
    }

    func testOneTimeFiresOnceAndDoesNotComeBackTomorrow() throws {
        try makeFixture()
        let item = addOneTimeHabit(dueIn: 60)

        clock = clock.addingTimeInterval(120)
        scheduler.tick()
        XCTAssertEqual(occurrences().count, 1)
        XCTAssertEqual(presenter.liveShown, 1)
        XCTAssertNil(item.nextFireDate, "nothing is scheduled after a one-time reminder")
        XCTAssertTrue(item.isOver)

        scheduler.markDone()

        // Two days later: still nothing.
        clock = clock.addingTimeInterval(2 * 86400)
        scheduler.tick()
        XCTAssertEqual(occurrences().count, 1)
        XCTAssertEqual(presenter.liveShown, 1)
    }

    func testSnoozedOneTimeStillComesBack() throws {
        try makeFixture()
        _ = addOneTimeHabit(dueIn: 60)

        clock = clock.addingTimeInterval(120)
        scheduler.tick()
        scheduler.snooze(minutes: 5)

        clock = clock.addingTimeInterval(6 * 60)
        scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 2, "a snoozed one-time reminder still comes back")
    }

    func testPausedOneTimeThatPassedIsNotRevived() throws {
        try makeFixture()
        let item = Item(title: "Read book", kind: .scheduledRoutine, hour: 12, minute: 0, style: .habit)
        item.onceAt = clock.addingTimeInterval(30)
        item.isActive = false
        item.pausedUntil = clock.addingTimeInterval(60)
        context.insert(item)

        clock = clock.addingTimeInterval(5 * 60)
        scheduler.tick()
        XCTAssertEqual(occurrences().count, 0)
        XCTAssertFalse(item.isActive)
        XCTAssertTrue(item.isOver)
    }
}
