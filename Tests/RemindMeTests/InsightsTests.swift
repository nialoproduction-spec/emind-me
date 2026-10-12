import XCTest
import SwiftData
@testable import RemindMe

/// History, streaks, the weekly summary and smart suggestions.
@MainActor
final class InsightsTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    /// Tuesday 2026-10-13, 18:00 UTC.
    private lazy var now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 18))!

    private func makeFixture() throws {
        container = try ModelContainer(
            for: Item.self, Occurrence.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
    }

    private func day(_ offset: Int, hour: Int = 9, minute: Int = 0) -> Date {
        let base = calendar.startOfDay(for: now)
        let day = calendar.date(byAdding: .day, value: offset, to: base)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    @discardableResult
    private func log(_ item: Item, _ date: Date, _ status: OccurrenceStatus,
                     resolvedAfter minutes: Double = 1, snoozed: Int? = nil) -> Occurrence {
        let occurrence = Occurrence(item: item, scheduledFireDate: date, calendar: calendar)
        occurrence.status = status
        if status == .done || status == .skipped {
            occurrence.resolvedAt = date.addingTimeInterval(minutes * 60)
        }
        occurrence.snoozedMinutes = snoozed
        context.insert(occurrence)
        return occurrence
    }

    private func all() -> [Occurrence] { (try? context.fetch(FetchDescriptor<Occurrence>())) ?? [] }

    // MARK: - Streaks

    func testStreakCountsKeptDaysBackFromToday() throws {
        try makeFixture()
        let walk = Item(title: "Walk", kind: .scheduledRoutine, hour: 9, minute: 0)
        context.insert(walk)
        log(walk, day(-4), .skipped)
        log(walk, day(-3), .done)
        log(walk, day(-2), .done)
        log(walk, day(-1), .done)
        log(walk, day(0), .pending) // today, not answered yet

        let records = Insights.dailyRecords(all(), days: 10, now: now, calendar: calendar)
        XCTAssertEqual(records.count, 10)
        XCTAssertEqual(records.last?.day, calendar.startOfDay(for: now), "ends today")
        XCTAssertEqual(Insights.streak(records), 3, "today in progress doesn't break it; the skip does")
    }

    func testDaysWithNothingScheduledDontBreakAStreak() throws {
        try makeFixture()
        let gym = Item(title: "Gym", kind: .scheduledRoutine, hour: 9, minute: 0, weekdaysRaw: [2, 4, 6])
        context.insert(gym)
        log(gym, day(-6), .done)
        log(gym, day(-4), .done)
        log(gym, day(-1), .done)
        let records = Insights.dailyRecords(all(), days: 14, now: now, calendar: calendar)
        XCTAssertEqual(Insights.streak(records), 3)
    }

    func testHalfDoneCountsAsKept() {
        XCTAssertTrue(Insights.DayRecord(day: now, done: 2, skipped: 2).isKept)
        XCTAssertFalse(Insights.DayRecord(day: now, done: 1, skipped: 2).isKept)
        XCTAssertFalse(Insights.DayRecord(day: now).isKept)
    }

    func testCompletionRateIgnoresWaitingOnes() throws {
        try makeFixture()
        let water = Item(title: "Water", kind: .repeatingRoutine, intervalSeconds: 3600)
        context.insert(water)
        log(water, day(-1, hour: 9), .done)
        log(water, day(-1, hour: 10), .done)
        log(water, day(-1, hour: 11), .skipped)
        log(water, day(-1, hour: 12), .unfinished)
        log(water, day(0, hour: 17), .pending)
        let records = Insights.dailyRecords(all(), days: 7, now: now, calendar: calendar)
        XCTAssertEqual(try XCTUnwrap(Insights.completionRate(records)), 0.5, accuracy: 0.001)
        XCTAssertNil(Insights.completionRate([]))
    }

    // MARK: - Weekly summary

    func testWeeklySummaryAddsUpTheLastSevenDays() throws {
        try makeFixture()
        let water = Item(title: "Water", kind: .repeatingRoutine, intervalSeconds: 3600, category: "Health")
        let walk = Item(title: "Walk", kind: .scheduledRoutine, hour: 9, minute: 0)
        let goal = Item(title: "Godavari", kind: .goal)
        [water, walk, goal].forEach { context.insert($0) }

        for offset in -6...0 { log(walk, day(offset), .done) }
        log(walk, day(-8), .done) // older than a week: not counted in the totals
        log(water, day(-2, hour: 10), .done, snoozed: 5)
        log(water, day(-2, hour: 11), .skipped, snoozed: 10)
        log(water, day(-1, hour: 10), .unfinished)

        let summary = Insights.weeklySummary(items: [water, walk, goal], occurrences: all(), now: now, calendar: calendar)
        XCTAssertEqual(summary.total, 10)
        XCTAssertEqual(summary.done, 8)
        XCTAssertEqual(summary.skipped, 1)
        XCTAssertEqual(summary.unfinished, 1)
        XCTAssertEqual(try XCTUnwrap(summary.rate), 0.8, accuracy: 0.001)
        XCTAssertEqual(summary.openGoals, 1)
        XCTAssertEqual(summary.bestStreak?.title, "Walk")
        XCTAssertEqual(summary.bestStreak?.streak, 8, "the day with nothing scheduled doesn't break it")
        XCTAssertEqual(summary.mostSnoozed?.title, "Water")
        XCTAssertEqual(summary.mostSnoozed?.snoozed, 2)
        XCTAssertEqual(summary.routines.first(where: { $0.title == "Water" })?.category, "Health")
    }

    func testWeekKeyChangesWeekToWeek() {
        let thisWeek = Insights.weekKey(for: now, calendar: calendar)
        XCTAssertEqual(thisWeek, Insights.weekKey(for: now.addingTimeInterval(3600), calendar: calendar))
        XCTAssertNotEqual(thisWeek, Insights.weekKey(for: now.addingTimeInterval(7 * 86400), calendar: calendar))
    }

    // MARK: - Smart suggestions

    func testSuggestsTheTimeYouActuallyDoIt() throws {
        try makeFixture()
        let walk = Item(title: "Walk", kind: .scheduledRoutine, hour: 16, minute: 0)
        context.insert(walk)
        log(walk, day(-3, hour: 16), .done, resolvedAfter: 33)
        log(walk, day(-2, hour: 16), .done, resolvedAfter: 37)
        log(walk, day(-1, hour: 16), .done, resolvedAfter: 35)

        let suggestions = Insights.suggestions(items: [walk], occurrences: all(), calendar: calendar)
        let suggestion = try XCTUnwrap(suggestions.first)
        XCTAssertEqual(suggestion.action, .moveTime(hour: 16, minute: 35))

        // Applied: the schedule moves, and it isn't suggested again.
        ItemActions.apply(suggestion, to: walk, now: now, reschedule: { _ in })
        XCTAssertEqual(walk.hour, 16)
        XCTAssertEqual(walk.minute, 35)
        XCTAssertNotNil(walk.scheduleEditedAt)
        XCTAssertTrue(Insights.suggestions(items: [walk], occurrences: all(), calendar: calendar).isEmpty)
    }

    func testNoTimeSuggestionWhenRoughlyOnTime() throws {
        try makeFixture()
        let walk = Item(title: "Walk", kind: .scheduledRoutine, hour: 16, minute: 0)
        context.insert(walk)
        for offset in -4...(-1) { log(walk, day(offset, hour: 16), .done, resolvedAfter: 8) }
        XCTAssertTrue(Insights.suggestions(items: [walk], occurrences: all(), calendar: calendar).isEmpty)
    }

    func testSuggestsSpacingOutAnOftenSnoozedRoutine() throws {
        try makeFixture()
        let water = Item(title: "Water", kind: .repeatingRoutine, intervalSeconds: 40 * 60)
        context.insert(water)
        log(water, day(-1, hour: 9), .done, snoozed: 15)
        log(water, day(-1, hour: 10), .done, snoozed: 20)
        log(water, day(-1, hour: 11), .done, snoozed: 15)
        log(water, day(-1, hour: 12), .done)

        let suggestion = try XCTUnwrap(Insights.suggestions(items: [water], occurrences: all(), calendar: calendar).first)
        XCTAssertEqual(suggestion.action, .setInterval(seconds: 55 * 60))
        XCTAssertTrue(suggestion.message.contains("Water"))
    }

    func testPausedRoutinesGetNoSuggestions() throws {
        try makeFixture()
        let water = Item(title: "Water", kind: .repeatingRoutine, isActive: false, intervalSeconds: 40 * 60)
        context.insert(water)
        for hour in 9...12 { log(water, day(-1, hour: hour), .done, snoozed: 15) }
        XCTAssertTrue(Insights.suggestions(items: [water], occurrences: all(), calendar: calendar).isEmpty)
    }

    // MARK: - Away

    func testAwayAfterTheChosenQuietTime() {
        var settings = SmartSettings()
        settings.awayMinutes = 3
        XCTAssertFalse(AwayDetector.isAway(idleSeconds: 120, settings: settings))
        XCTAssertTrue(AwayDetector.isAway(idleSeconds: 180, settings: settings))
        settings.holdWhileAway = false
        XCTAssertFalse(AwayDetector.isAway(idleSeconds: 3600, settings: settings))
    }
}
