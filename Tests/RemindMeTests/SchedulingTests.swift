import XCTest
@testable import RemindMe

/// Next-fire-time math. Uses a fixed Kathmandu calendar and fixed dates so
/// results never depend on the machine's clock or time zone.
final class SchedulingTests: XCTestCase {

    private var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kathmandu")!
        return cal
    }()

    /// 2026-10-13 is a Tuesday.
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func scheduled(hour: Int, minute: Int = 0, weekdays: [Int]? = nil) -> Item {
        Item(title: "t", kind: .scheduledRoutine, hour: hour, minute: minute, weekdaysRaw: weekdays)
    }

    func testDailyLaterToday() {
        let item = scheduled(hour: 16)
        XCTAssertEqual(item.computeNextFireDate(after: date(13, 9), calendar: calendar), date(13, 16))
    }

    func testDailyAlreadyPassedRollsToTomorrow() {
        let item = scheduled(hour: 4)
        XCTAssertEqual(item.computeNextFireDate(after: date(13, 9), calendar: calendar), date(14, 4))
    }

    func testExactlyAtFireTimeMovesToNextDay() {
        // Right after firing, the next one must be tomorrow — not the same instant again.
        let item = scheduled(hour: 7)
        XCTAssertEqual(item.computeNextFireDate(after: date(13, 7), calendar: calendar), date(14, 7))
    }

    func testWeekdayFilterSkipsToNextMatchingDay() {
        // Mondays only (weekday 2). From Tuesday 13 Oct -> Monday 19 Oct.
        let item = scheduled(hour: 18, weekdays: [2])
        XCTAssertEqual(item.computeNextFireDate(after: date(13, 9), calendar: calendar), date(19, 18))
    }

    func testWeekdayFilterSameDayStillAhead() {
        // Tuesdays (3), asked Tuesday morning -> this evening.
        let item = scheduled(hour: 18, minute: 30, weekdays: [3])
        XCTAssertEqual(item.computeNextFireDate(after: date(13, 9), calendar: calendar), date(13, 18, 30))
    }

    func testWeekdayFilterSameDayAlreadyPassedGoesAWeekOut() {
        let item = scheduled(hour: 6, weekdays: [3])
        XCTAssertEqual(item.computeNextFireDate(after: date(13, 9), calendar: calendar), date(20, 6))
    }

    func testCrossesMonthEnd() {
        let item = scheduled(hour: 5)
        XCTAssertEqual(item.computeNextFireDate(after: date(31, 23), calendar: calendar),
                       date(1, 5, month: 11))
    }

    func testRepeatingIsReferencePlusInterval() {
        let item = Item(title: "t", kind: .repeatingRoutine, intervalSeconds: 40 * 60)
        let ref = date(13, 10)
        XCTAssertEqual(item.computeNextFireDate(after: ref, calendar: calendar), ref.addingTimeInterval(2400))
    }

    func testGoalsNeverGetAFireTime() {
        let item = Item(title: "Go to Godavari", kind: .goal)
        XCTAssertNil(item.computeNextFireDate(after: date(13, 10), calendar: calendar))
    }

    // MARK: - End-of-day summary trigger

    private func eod(enabled: Bool = true, hour: Int = 21, minute: Int = 0, shownOn: String? = nil) -> EndOfDaySettings {
        var s = EndOfDaySettings()
        s.isEnabled = enabled
        s.hour = hour
        s.minute = minute
        s.lastShownDayKey = shownOn
        return s
    }

    func testEndOfDayNotBeforeItsTime() {
        XCTAssertFalse(ReminderScheduler.shouldShowEndOfDay(settings: eod(), now: date(13, 20, 59), calendar: calendar))
    }

    func testEndOfDayAtItsTime() {
        XCTAssertTrue(ReminderScheduler.shouldShowEndOfDay(settings: eod(), now: date(13, 21), calendar: calendar))
    }

    func testEndOfDayStillShowsIfMacWasAsleepAtItsTime() {
        // Woke at 22:47 — the 21:00 summary must still appear, not be skipped for the day.
        XCTAssertTrue(ReminderScheduler.shouldShowEndOfDay(settings: eod(), now: date(13, 22, 47), calendar: calendar))
    }

    func testEndOfDayOnlyOncePerDay() {
        XCTAssertFalse(ReminderScheduler.shouldShowEndOfDay(
            settings: eod(shownOn: "2026-10-13"), now: date(13, 22), calendar: calendar))
    }

    func testEndOfDayOffMeansOff() {
        XCTAssertFalse(ReminderScheduler.shouldShowEndOfDay(settings: eod(enabled: false), now: date(13, 22), calendar: calendar))
    }
}
