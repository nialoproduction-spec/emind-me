import XCTest
@testable import RemindMe

/// The self-check's rules: which reminders need a notification, and which
/// ones have none waiting. Pure, so no notification centre is touched.
final class HealthCheckTests: XCTestCase {
    private func habit(_ title: String, active: Bool = true, ended: Bool = false) -> Item {
        let item = Item(title: title, kind: .repeatingRoutine, isActive: active, intervalSeconds: 40 * 60)
        if ended { item.endedAt = .now }
        return item
    }

    func testActiveHabitWithNoNotificationIsMissing() {
        let item = habit("Drink water")
        XCTAssertEqual(ScheduleAudit.missing(among: [item], pending: []).map(\.id), [item.id])
    }

    func testPendingNotificationByIDCountsAsPresent() {
        let item = habit("Drink water")
        XCTAssertTrue(ScheduleAudit.missing(among: [item], pending: [item.id.uuidString]).isEmpty)
    }

    func testWeekdayNotificationCountsAsPresent() {
        let item = habit("Gym")
        XCTAssertTrue(ScheduleAudit.missing(among: [item], pending: ["\(item.id.uuidString).3"]).isEmpty)
    }

    func testAnotherItemsNotificationDoesNotCount() {
        let item = habit("Gym")
        let other = UUID().uuidString
        XCTAssertEqual(ScheduleAudit.missing(among: [item], pending: [other]).map(\.id), [item.id])
    }

    func testGoalsPausedAndFinishedItemsAreNotChecked() {
        let goal = Item(title: "Go to Godavari", kind: .goal)
        let paused = habit("Paused", active: false)
        let finished = habit("Finished", ended: true)
        XCTAssertTrue(ScheduleAudit.missing(among: [goal, paused, finished], pending: []).isEmpty)
    }

    func testRepairLogKeepsNewestFirstAndCaps() {
        var log = RepairLog()
        for i in 0..<(RepairLog.limit + 5) {
            log.add("repair \(i)", at: Date(timeIntervalSince1970: TimeInterval(i)))
        }
        XCTAssertEqual(log.entries.count, RepairLog.limit)
        XCTAssertEqual(log.entries.first?.text, "repair \(RepairLog.limit + 4)")
    }
}
