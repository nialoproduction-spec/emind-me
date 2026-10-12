import XCTest
import SwiftData
@testable import RemindMe

/// Editing a reminder's schedule, and pause lengths.
@MainActor
final class ItemActionsTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var rescheduled: [String] = []

    private func reschedule(_ item: Item) { rescheduled.append(item.title) }

    func testEditingTheIntervalTakesEffectFromNow() {
        let item = Item(title: "Water", kind: .repeatingRoutine, intervalSeconds: 40 * 60)
        item.nextFireDate = now.addingTimeInterval(-600)
        var edit = ItemActions.Edit(of: item)
        edit.intervalSeconds = 90 * 60
        edit.title = "  Drink water  "
        ItemActions.apply(edit, to: item, now: now, reschedule: reschedule)

        XCTAssertEqual(item.intervalSeconds, 90 * 60)
        XCTAssertEqual(item.title, "Drink water")
        XCTAssertEqual(item.nextFireDate, now.addingTimeInterval(90 * 60))
        XCTAssertEqual(item.scheduleEditedAt, now)
        XCTAssertEqual(rescheduled, ["Drink water"])
    }

    func testSwitchingToATimeOnChosenDays() {
        let item = Item(title: "Gym", kind: .repeatingRoutine, intervalSeconds: 3600)
        var edit = ItemActions.Edit(of: item)
        edit.kind = .scheduledRoutine
        edit.hour = 7
        edit.minute = 15
        edit.weekdays = [6, 2, 4, 2]
        ItemActions.apply(edit, to: item, now: now, reschedule: reschedule)

        XCTAssertEqual(item.kind, .scheduledRoutine)
        XCTAssertNil(item.intervalSeconds)
        XCTAssertEqual(item.weekdaysRaw, [2, 4, 6])
        XCTAssertEqual(item.scheduleSummary.isEmpty, false)
        let next = try? XCTUnwrap(item.nextFireDate)
        XCTAssertNotNil(next)
        if let next {
            let parts = Calendar.current.dateComponents([.hour, .minute, .weekday], from: next)
            XCTAssertEqual(parts.hour, 7)
            XCTAssertEqual(parts.minute, 15)
            XCTAssertTrue([2, 4, 6].contains(parts.weekday!))
        }
    }

    func testAllSevenDaysMeansEveryDay() {
        let item = Item(title: "Walk", kind: .scheduledRoutine, hour: 6, minute: 0, weekdaysRaw: [2])
        var edit = ItemActions.Edit(of: item)
        edit.weekdays = Array(1...7)
        ItemActions.apply(edit, to: item, now: now, reschedule: reschedule)
        XCTAssertNil(item.weekdaysRaw)
    }

    func testTurningIntoAGoalStopsReminding() {
        let item = Item(title: "Godavari", kind: .repeatingRoutine, intervalSeconds: 3600)
        item.nextFireDate = now
        var edit = ItemActions.Edit(of: item)
        edit.kind = .goal
        edit.targetDate = now.addingTimeInterval(86400 * 30)
        ItemActions.apply(edit, to: item, now: now, reschedule: reschedule)
        XCTAssertEqual(item.kind, .goal)
        XCTAssertNil(item.nextFireDate)
        XCTAssertNil(item.intervalSeconds)
        XCTAssertNotNil(item.targetDate)
    }

    func testRenameOnlyKeepsTheNextReminder() {
        let item = Item(title: "Water", kind: .repeatingRoutine, intervalSeconds: 3600)
        let next = now.addingTimeInterval(1234)
        item.nextFireDate = next
        var edit = ItemActions.Edit(of: item)
        edit.title = "Water plants"
        edit.category = "Home"
        ItemActions.apply(edit, to: item, now: now, reschedule: reschedule)
        XCTAssertEqual(item.nextFireDate, next, "same schedule: the next reminder doesn't move")
        XCTAssertNil(item.scheduleEditedAt)
        XCTAssertEqual(item.category, "Home")
    }

    func testInvalidEditsAreIgnored() {
        let item = Item(title: "Water", kind: .repeatingRoutine, intervalSeconds: 3600)
        var edit = ItemActions.Edit(of: item)
        edit.title = "   "
        XCTAssertFalse(edit.isValid)
        ItemActions.apply(edit, to: item, now: now, reschedule: reschedule)
        XCTAssertEqual(item.title, "Water")

        edit = ItemActions.Edit(of: item)
        edit.intervalSeconds = 10
        XCTAssertFalse(edit.isValid, "less than a minute apart")
    }

    func testEmptyCategoryClearsIt() {
        let item = Item(title: "Water", kind: .repeatingRoutine, intervalSeconds: 3600, category: "Health")
        var edit = ItemActions.Edit(of: item)
        edit.category = "  "
        ItemActions.apply(edit, to: item, now: now, reschedule: reschedule)
        XCTAssertNil(item.category)
    }

    func testResumeRecomputesFromNow() {
        let item = Item(title: "Water", kind: .repeatingRoutine, isActive: false, intervalSeconds: 600)
        item.pausedUntil = now.addingTimeInterval(3600)
        ItemActions.resume(item, now: now, reschedule: reschedule)
        XCTAssertTrue(item.isActive)
        XCTAssertNil(item.pausedUntil)
        XCTAssertEqual(item.nextFireDate, now.addingTimeInterval(600))
        XCTAssertEqual(rescheduled, ["Water"])
    }

    func testPauseLengths() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 22, minute: 10))!
        XCTAssertEqual(ItemActions.PauseLength.oneHour.endDate(from: start, calendar: calendar),
                       start.addingTimeInterval(3600))
        XCTAssertEqual(ItemActions.PauseLength.untilTomorrow.endDate(from: start, calendar: calendar),
                       calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 6)))
        XCTAssertEqual(ItemActions.PauseLength.oneWeek.endDate(from: start, calendar: calendar),
                       calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 22, minute: 10)))
        XCTAssertNil(ItemActions.PauseLength.indefinitely.endDate(from: start, calendar: calendar))
    }
}
