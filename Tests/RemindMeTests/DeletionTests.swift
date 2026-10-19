import XCTest
import SwiftData
@testable import RemindMe

/// Deleting a routine removes its occurrences too, and the startup repair
/// clears leftovers from older builds.
@MainActor
final class DeletionTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var presenter: FakePresenter!
    private var scheduler: ReminderScheduler!
    private var cancelled: [String] = []
    private let clock = Date(timeIntervalSinceReferenceDate: 800_000_000)

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
            resumed: { _ in },
            weeklySettings: .testing(WeeklySummarySettings(isEnabled: false)),
            goalNudgeSettings: .testing(GoalNudgeSettings(isEnabled: false)),
            showNotice: { _ in }
        )
        scheduler.attach(modelContext: context)
    }

    @discardableResult
    private func addRoutine(_ title: String, occurrences: Int = 0) -> Item {
        let item = Item(title: title, kind: .repeatingRoutine, intervalSeconds: 600 * 60)
        item.nextFireDate = clock.addingTimeInterval(3600)
        context.insert(item)
        for i in 0..<occurrences {
            context.insert(Occurrence(item: item, scheduledFireDate: clock.addingTimeInterval(Double(-i) * 60)))
        }
        try? context.save()
        return item
    }

    private func delete(_ item: Item) {
        ItemDeletion.delete(item, in: context, scheduler: scheduler,
                            cancelNotifications: { [unowned self] item in self.cancelled.append(item.title) })
    }

    private func count<T: PersistentModel>(_ type: T.Type) -> Int {
        (try? context.fetch(FetchDescriptor<T>()).count) ?? -1
    }

    // MARK: - Cascade

    func testDeletingARoutineDeletesItsOccurrences() throws {
        try makeFixture()
        let water = addRoutine("Drink water", occurrences: 2)
        addRoutine("Stretch", occurrences: 1)

        delete(water)

        XCTAssertEqual(count(Item.self), 1)
        XCTAssertEqual(count(Occurrence.self), 1, "only Stretch's occurrence is left")
        let remaining = try context.fetch(FetchDescriptor<Occurrence>())
        XCTAssertEqual(remaining.first?.item?.title, "Stretch")
        XCTAssertEqual(cancelled, ["Drink water"], "its notifications are cancelled")
    }

    func testDeletingAGoalWorks() throws {
        try makeFixture()
        let goal = Item(title: "Go to Godavari", kind: .goal)
        context.insert(goal)
        delete(goal)
        XCTAssertEqual(count(Item.self), 0)
    }

    func testSchedulerKeepsWorkingAfterADelete() throws {
        try makeFixture()
        let water = addRoutine("Drink water", occurrences: 2)
        let stretch = addRoutine("Stretch")
        delete(water)
        stretch.nextFireDate = clock
        scheduler.tick() // used to be where the crash happened
        XCTAssertEqual(scheduler.activeOccurrence?.item?.title, "Stretch")
    }

    func testDeletingTheRoutineOnScreenClosesItsReminderFirst() async throws {
        try makeFixture()
        let water = addRoutine("Drink water")
        water.nextFireDate = clock
        scheduler.tick()
        XCTAssertNotNil(scheduler.activeOccurrence)

        delete(water)
        XCTAssertNil(scheduler.activeOccurrence, "its reminder closes right away")
        XCTAssertEqual(presenter.liveDismissed, 1)

        // The data goes once the card has faded out.
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(count(Item.self), 0)
        XCTAssertEqual(count(Occurrence.self), 0)
    }

    func testDeletingAnotherRoutineLeavesTheReminderOnScreen() throws {
        try makeFixture()
        let water = addRoutine("Drink water")
        let stretch = addRoutine("Stretch")
        water.nextFireDate = clock
        scheduler.tick()
        delete(stretch)
        XCTAssertEqual(scheduler.activeOccurrence?.item?.title, "Drink water")
        XCTAssertEqual(presenter.liveDismissed, 0)
    }
}

/// The startup repair, against a real on-disk store like the one on the Mac.
@MainActor
final class StoreRepairTests: XCTestCase {
    private let schema = Schema([Item.self, Occurrence.self])

    private func freshStoreURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("test.store")
    }

    private func open(_ url: URL) throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
    }

    /// Writes a routine with one occurrence, then deletes the routine the way
    /// older builds did (the item only).
    private func makeOldStyleOrphan(at url: URL) throws {
        let container = try open(url)
        let context = ModelContext(container)
        let item = Item(title: "Drink water", kind: .repeatingRoutine, intervalSeconds: 60)
        context.insert(item)
        context.insert(Occurrence(item: item, scheduledFireDate: .now))
        try context.save()
        context.delete(item)
        try context.save()
    }

    func testOldStyleDeleteLeftAnOrphanAndRepairRemovesIt() throws {
        let url = try freshStoreURL()
        try makeOldStyleOrphan(at: url)

        XCTAssertEqual(StoreRepair.orphanCount(storeURL: url), 1,
                       "deleting only the item leaves its occurrence pointing at nothing — the launch crash")
        XCTAssertEqual(StoreRepair.removeOrphanedOccurrences(storeURL: url), 1)
        XCTAssertEqual(StoreRepair.orphanCount(storeURL: url), 0)

        // Next launch: the store opens and the scheduler runs over it.
        let container = try open(url)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Occurrence>()).count, 0)
        let scheduler = ReminderScheduler(presenter: FakePresenter(), shouldSuppress: { false },
                                          isAway: { false }, resumed: { _ in },
                                          weeklySettings: .testing(WeeklySummarySettings(isEnabled: false)),
                                          goalNudgeSettings: .testing(GoalNudgeSettings(isEnabled: false)),
                                          showNotice: { _ in })
        scheduler.attach(modelContext: container.mainContext)
        scheduler.tick()
    }

    func testRepairLeavesHealthyDataAlone() throws {
        let url = try freshStoreURL()
        do {
            let container = try open(url)
            let context = ModelContext(container)
            let item = Item(title: "Stretch", kind: .repeatingRoutine, intervalSeconds: 60)
            context.insert(item)
            context.insert(Occurrence(item: item, scheduledFireDate: .now))
            try context.save()
        }
        XCTAssertEqual(StoreRepair.removeOrphanedOccurrences(storeURL: url), 0)
        let container = try open(url)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Occurrence>()).count, 1)
    }

    func testNewDeleteLeavesNoOrphansOnDisk() throws {
        let url = try freshStoreURL()
        do {
            let container = try open(url)
            let context = ModelContext(container)
            let item = Item(title: "Drink water", kind: .repeatingRoutine, intervalSeconds: 60)
            context.insert(item)
            context.insert(Occurrence(item: item, scheduledFireDate: .now))
            context.insert(Occurrence(item: item, scheduledFireDate: .now))
            try context.save()
            ItemDeletion.removeData(of: item, in: context)
        }
        XCTAssertEqual(StoreRepair.orphanCount(storeURL: url), 0)
        let container = try open(url)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Occurrence>()).count, 0)
    }

    func testRepairWithNoStoreYetDoesNothing() throws {
        let url = try freshStoreURL()
        XCTAssertEqual(StoreRepair.removeOrphanedOccurrences(storeURL: url), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "doesn't create a database")
    }
}
