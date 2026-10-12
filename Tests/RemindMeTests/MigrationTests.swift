import XCTest
import SwiftData
@testable import RemindMe

/// The database shape the installed builds (up to build 10) wrote, before
/// pause-until, categories, snooze minutes and schedule-edit times were added.
enum StoreV1 {
    @Model
    final class Item {
        var id: UUID
        var title: String
        var kindRaw: Int
        var createdAt: Date
        var isActive: Bool
        var isAchieved: Bool
        var intervalSeconds: Double?
        var hour: Int?
        var minute: Int?
        var weekdaysRaw: [Int]?
        var targetDate: Date?
        var nextFireDate: Date?

        init(title: String, intervalSeconds: Double, nextFireDate: Date) {
            id = UUID()
            self.title = title
            kindRaw = ItemKind.repeatingRoutine.rawValue
            createdAt = .now
            isActive = true
            isAchieved = false
            self.intervalSeconds = intervalSeconds
            hour = nil
            minute = nil
            weekdaysRaw = nil
            targetDate = nil
            self.nextFireDate = nextFireDate
        }
    }

    @Model
    final class Occurrence {
        var id: UUID
        var item: Item?
        var dayKey: String
        var scheduledFireDate: Date
        var statusRaw: Int
        var remindersSentCount: Int
        var firstFiredAt: Date?
        var nextEscalationAt: Date?
        var resolvedAt: Date?

        init(item: Item, at date: Date, status: OccurrenceStatus) {
            id = UUID()
            self.item = item
            dayKey = RemindMe.Occurrence.dayKey(for: date)
            scheduledFireDate = date
            statusRaw = status.rawValue
            remindersSentCount = 1
            firstFiredAt = date
            nextEscalationAt = nil
            resolvedAt = status == .done ? date : nil
        }
    }
}

/// Updating the app must keep everyone's reminders: a store written by the
/// previous build opens with this one, data intact, new fields empty.
@MainActor
final class MigrationTests: XCTestCase {
    func testOldStoreOpensWithTheNewFields() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("remindme-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("default.store")
        let due = Date(timeIntervalSinceReferenceDate: 800_000_000)

        do {
            let old = try ModelContainer(
                for: StoreV1.Item.self, StoreV1.Occurrence.self,
                configurations: ModelConfiguration(url: url)
            )
            let context = ModelContext(old)
            let item = StoreV1.Item(title: "Drink water", intervalSeconds: 2400, nextFireDate: due)
            context.insert(item)
            context.insert(StoreV1.Occurrence(item: item, at: due.addingTimeInterval(-2400), status: .done))
            try context.save()
        }

        let schema = Schema([RemindMe.Item.self, RemindMe.Occurrence.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        let context = container.mainContext
        let items = try context.fetch(FetchDescriptor<RemindMe.Item>())
        XCTAssertEqual(items.count, 1)
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.title, "Drink water")
        XCTAssertEqual(item.intervalSeconds, 2400)
        XCTAssertEqual(item.nextFireDate, due)
        XCTAssertNil(item.pausedUntil)
        XCTAssertNil(item.category)
        XCTAssertNil(item.scheduleEditedAt)

        let occurrences = try context.fetch(FetchDescriptor<RemindMe.Occurrence>())
        XCTAssertEqual(occurrences.count, 1)
        XCTAssertEqual(occurrences.first?.status, .done)
        XCTAssertNil(occurrences.first?.snoozedMinutes)
        XCTAssertEqual(occurrences.first?.item?.title, "Drink water", "the link survives")

        // And it's usable: new fields can be written and read back.
        item.category = "Health"
        item.pausedUntil = due
        occurrences.first?.snoozedMinutes = 15
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<RemindMe.Item>()).first?.category, "Health")
    }
}
