import XCTest
@testable import RemindMe

/// Next due time for the schedules beyond one time a day.
final class ScheduleExtrasTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private func interval(_ seconds: Double, days: [Int]? = nil, _ rules: ScheduleExtras) -> Item {
        let item = Item(title: "Drink water", kind: .repeatingRoutine, intervalSeconds: seconds, weekdaysRaw: days)
        item.extras = rules
        return item
    }

    private func clock(_ hour: Int, minute: Int = 0, days: [Int]? = nil, _ rules: ScheduleExtras) -> Item {
        let item = Item(title: "Pills", kind: .scheduledRoutine, hour: hour, minute: minute, weekdaysRaw: days)
        item.extras = rules
        return item
    }

    func testActiveHoursKeepItInsideTheWindow() {
        let item = interval(40 * 60, ScheduleExtras(windowStart: 540, windowEnd: 1080))
        // 10:00 + 40 min is inside.
        XCTAssertEqual(item.computeNextFireDate(after: date(2026, 11, 10, 10), calendar: calendar), date(2026, 11, 10, 10, 40))
        // 17:50 + 40 min is past 6 PM: next morning at 9.
        XCTAssertEqual(item.computeNextFireDate(after: date(2026, 11, 10, 17, 50), calendar: calendar), date(2026, 11, 11, 9))
    }

    func testWindowPastMidnight() {
        let item = interval(60 * 60, ScheduleExtras(windowStart: 22 * 60, windowEnd: 2 * 60))
        XCTAssertEqual(item.computeNextFireDate(after: date(2026, 11, 10, 23), calendar: calendar), date(2026, 11, 11, 0))
        XCTAssertEqual(item.computeNextFireDate(after: date(2026, 11, 11, 2), calendar: calendar), date(2026, 11, 11, 22))
    }

    func testIntervalOnWeekdaysOnlyWaitsForMonday() {
        let item = interval(60 * 60, days: [2, 3, 4, 5, 6], ScheduleExtras())
        // Friday 23:30 + 1 h is Saturday: Monday 9 AM.
        XCTAssertEqual(item.computeNextFireDate(after: date(2026, 11, 13, 23, 30), calendar: calendar), date(2026, 11, 16, 9))
    }

    func testSeveralTimesADay() {
        let item = clock(9, ScheduleExtras(extraTimes: [21 * 60]))
        XCTAssertEqual(item.computeNextFireDate(after: date(2026, 11, 10, 10), calendar: calendar), date(2026, 11, 10, 21))
        XCTAssertEqual(item.computeNextFireDate(after: date(2026, 11, 10, 22), calendar: calendar), date(2026, 11, 11, 9))
    }

    func testEveryOtherDay() {
        let item = clock(7, ScheduleExtras(dayStep: 2, anchor: date(2026, 11, 10, 10)))
        // Tuesday 7 AM has gone: Thursday.
        XCTAssertEqual(item.computeNextFireDate(after: date(2026, 11, 10, 10), calendar: calendar), date(2026, 11, 12, 7))
        XCTAssertEqual(item.computeNextFireDate(after: date(2026, 11, 12, 7), calendar: calendar), date(2026, 11, 14, 7))
    }

    func testEveryOtherFriday() {
        let item = clock(9, days: [6], ScheduleExtras(weekStep: 2, anchor: date(2026, 11, 9)))
        XCTAssertEqual(item.computeNextFireDate(after: date(2026, 11, 10), calendar: calendar), date(2026, 11, 13, 9))
        XCTAssertEqual(item.computeNextFireDate(after: date(2026, 11, 13, 9), calendar: calendar), date(2026, 11, 27, 9))
    }

    func testFirstMondayOfTheMonth() {
        let item = clock(9, days: [2], ScheduleExtras(monthWeek: 1))
        // Nov 2 has gone: Dec 7 (Dec 1 2026 is a Tuesday).
        XCTAssertEqual(item.computeNextFireDate(after: date(2026, 11, 10), calendar: calendar), date(2026, 12, 7, 9))
    }

    func testLastFridayOfTheMonth() {
        let item = clock(9, days: [6], ScheduleExtras(monthWeek: -1))
        XCTAssertEqual(item.computeNextFireDate(after: date(2026, 11, 10), calendar: calendar), date(2026, 11, 27, 9))
    }

    func testEndsOnStopsIt() {
        let item = clock(9, ScheduleExtras(endsOn: date(2026, 11, 12, 23, 59)))
        XCTAssertEqual(item.computeNextFireDate(after: date(2026, 11, 11, 10), calendar: calendar), date(2026, 11, 12, 9))
        XCTAssertNil(item.computeNextFireDate(after: date(2026, 11, 12, 9), calendar: calendar))
    }

    func testExtrasRoundTripAndEmptyIsNil() {
        let item = clock(9, ScheduleExtras(extraTimes: [1260]))
        XCTAssertNotNil(item.extrasData)
        XCTAssertEqual(item.extras.extraTimes, [1260])
        item.extras = ScheduleExtras()
        XCTAssertNil(item.extrasData)
    }

    func testOneShotNotificationForRulesAndLongMonths() {
        XCTAssertTrue(clock(9, ScheduleExtras(extraTimes: [1260])).usesOneShotNotification)
        XCTAssertFalse(clock(9, ScheduleExtras()).usesOneShotNotification)
        let rent = clock(9, ScheduleExtras())
        rent.monthDay = 31
        XCTAssertTrue(rent.usesOneShotNotification, "the 31st doesn't exist in short months")
    }

    func testSummaries() {
        XCTAssertEqual(ScheduleExtras.dayList([2, 3, 4, 5, 6]), "Weekdays")
        XCTAssertEqual(ScheduleExtras.dayList([1, 7]), "Weekends")
        XCTAssertTrue(clock(7, ScheduleExtras(dayStep: 2)).scheduleSummary.hasSuffix("Every 2 days"))
        XCTAssertTrue(clock(9, days: [2], ScheduleExtras(monthWeek: 1)).scheduleSummary.contains("First Mon of the month"))
        XCTAssertTrue(interval(3600, ScheduleExtras(windowStart: 540, windowEnd: 1080)).scheduleSummary.hasPrefix("every 1 hour"))
    }

    func testNotYetStartsTheRedCountAtZero() {
        var timers = TaskTimers()
        let t0 = Date(timeIntervalSince1970: 1_000)
        timers.start(title: "Edit", category: nil, seconds: 60, at: t0)
        let id = timers.entries[0].id
        _ = timers.advance(now: t0.addingTimeInterval(60))
        let pressed = t0.addingTimeInterval(75)
        timers.notYet(id, now: pressed)
        XCTAssertEqual(timers.entries[0].overdueAt, pressed)
    }
}
