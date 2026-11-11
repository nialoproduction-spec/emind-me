import XCTest
@testable import RemindMe

/// Reminders that popped up wait at the bottom of the panel until ticked.
final class TickListTests: XCTestCase {
    func testAddTickAndOneEntryPerReminder() {
        var list = TickList()
        let water = UUID()
        let t = Date(timeIntervalSince1970: 1_000)
        list.add(itemID: water, title: "Drink water", at: t)
        list.add(itemID: UUID(), title: "Call mom", at: t)
        list.add(itemID: water, title: "Drink water", at: t.addingTimeInterval(60))
        XCTAssertEqual(list.entries.count, 2, "the same reminder isn't listed twice")
        XCTAssertEqual(list.entries.first?.title, "Drink water", "newest first")

        list.tick(list.entries[0].id)
        XCTAssertEqual(list.entries.map(\.title), ["Call mom"])
    }

    func testForgetWhenTheReminderIsDeleted() {
        var list = TickList()
        let id = UUID()
        list.add(itemID: id, title: "Pay rent", at: .now, missed: true)
        XCTAssertTrue(list.entries[0].missed)
        list.forget(itemID: id)
        XCTAssertTrue(list.entries.isEmpty)
    }

    func testTimerEditAndDelete() {
        var timers = TaskTimers()
        let t0 = Date(timeIntervalSince1970: 1_000)
        timers.start(title: "Select sound", category: nil, seconds: 1200, at: t0)
        timers.start(title: "Edit video", category: nil, seconds: 1200, at: t0)
        let first = timers.entries.last!.id
        let second = timers.entries.first!.id

        timers.update(first, title: "Pick music", seconds: 600, now: t0)
        XCTAssertEqual(timers.entries.first { $0.id == first }?.title, "Pick music")
        XCTAssertEqual(timers.entries.first { $0.id == first }?.seconds, 600)

        timers.remove(first, now: t0.addingTimeInterval(30))
        XCTAssertEqual(timers.current?.id, second, "deleting the running one starts the next")
        XCTAssertEqual(timers.current?.startedAt, t0.addingTimeInterval(30))
    }
}
