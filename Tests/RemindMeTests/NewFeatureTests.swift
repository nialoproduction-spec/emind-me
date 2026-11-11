import XCTest
import SwiftData
@testable import RemindMe

/// The render ping, the habit calendar, the missed list and undo: their
/// pure parts.
@MainActor
final class NewFeatureTests: XCTestCase {
    func testRenderIsDoneOnceTheFileStopsGrowing() {
        var tracker = RenderTracker()
        let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let path = "/Renders/Sharma teaser.mov"
        tracker.touched(path, size: 100, now: t0)
        XCTAssertEqual(tracker.check(sizes: [path: 5_000], now: t0 + 3), [])
        XCTAssertEqual(tracker.check(sizes: [path: 9_000], now: t0 + 6), [], "still growing")
        XCTAssertEqual(tracker.check(sizes: [path: 9_000], now: t0 + 12), [], "quiet, but not long enough")
        XCTAssertEqual(tracker.check(sizes: [path: 9_000], now: t0 + 19), [path], "stopped growing: done")
        XCTAssertTrue(tracker.isEmpty, "said once")

        tracker.touched("/Renders/old.mov", size: 500, now: t0)
        XCTAssertEqual(tracker.check(sizes: ["/Renders/old.mov": 500], now: t0 + 13), [], "touched, never grew")
        XCTAssertTrue(tracker.isEmpty)

        tracker.touched("/Renders/temp.mov", size: 10, now: t0)
        XCTAssertEqual(tracker.check(sizes: ["/Renders/temp.mov": nil], now: t0 + 3), [], "gone")
        XCTAssertTrue(tracker.isEmpty)

        XCTAssertFalse(RenderTracker.isRenderFile("/Renders/.partial.mov"))
        XCTAssertFalse(RenderTracker.isRenderFile("/Renders/notes.txt"))
        XCTAssertTrue(RenderTracker.isRenderFile("/Renders/Final.MP4"))
    }

    func testMonthGridLaysOutWeeks() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 1
        let october = cal.date(from: DateComponents(year: 2026, month: 10, day: 15))!
        let container = try ModelContainer(for: Item.self, Occurrence.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let item = Item(title: "Stretch", kind: .repeatingRoutine, intervalSeconds: 3600)
        container.mainContext.insert(item)
        let done = Occurrence(item: item, scheduledFireDate: cal.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 9))!,
                              calendar: cal)
        container.mainContext.insert(done)
        done.status = .done
        let weeks = Insights.monthGrid([done], month: october, calendar: cal)
        XCTAssertEqual(weeks.count, 5)
        XCTAssertTrue(weeks.allSatisfy { $0.count == 7 })
        XCTAssertNil(weeks[0][3], "1 Oct 2026 is a Thursday")
        XCTAssertEqual(weeks[0][4].map { cal.component(.day, from: $0.day) }, 1)
        XCTAssertEqual(weeks[0][5]?.done, 1, "done on the 2nd")
        XCTAssertEqual(weeks.flatMap { $0 }.compactMap { $0 }.count, 31)
    }

    func testMissedListCountsRepeats() {
        var list = MissedList()
        let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
        list.add(title: "Drink water", dueAt: t0 + 60)
        list.add(title: "Msg wife", dueAt: t0 + 30)
        list.add(title: "Drink water", dueAt: t0, count: 2)
        XCTAssertEqual(list.entries.map(\.title), ["Drink water", "Msg wife"], "oldest first")
        XCTAssertEqual(list.entries.first?.count, 3)
        XCTAssertEqual(list.entries.first?.dueAt, t0, "keeps the first time")
    }

    func testUndoOnlyForTenMinutes() {
        var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let undo = UndoCenter(now: { now })
        var undone = 0
        undo.record("Done: Stretch") { undone += 1 }
        now += 11 * 60
        XCTAssertNil(undo.available)
        XCTAssertFalse(undo.undoLast())
        XCTAssertEqual(undone, 0)
        undo.record("Skipped: Stretch") { undone += 1 }
        XCTAssertTrue(undo.undoLast())
        XCTAssertEqual(undone, 1)
    }

    func testIgnoreCountsGetLoudAtThree() {
        var counts = IgnoreCounts()
        let id = UUID()
        counts.ignored(id)
        counts.ignored(id)
        XCTAssertFalse(counts.isLoud(id))
        counts.ignored(id)
        XCTAssertTrue(counts.isLoud(id))
        counts.answered(id)
        XCTAssertEqual(counts.count(for: id), 0)
    }
}
