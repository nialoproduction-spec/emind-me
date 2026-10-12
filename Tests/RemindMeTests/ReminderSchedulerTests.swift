import XCTest
import SwiftData
@testable import RemindMe

/// Records what the scheduler asked the screen to do, instead of showing windows.
@MainActor
final class FakePresenter: LiveReminderPresenting {
    var liveShown = 0
    var liveDismissed = 0
    var overlayShown = 0
    func presentLiveReminder() { liveShown += 1 }
    func dismissLiveReminder() { liveDismissed += 1 }
    func presentOverlay() { overlayShown += 1 }
    func dismissOverlay() {}
}

/// The reliability-critical part: firing, escalation, snooze, sleep catch-up
/// and Focus suppression, driven by a fake clock so minutes pass instantly.
@MainActor
final class ReminderSchedulerTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var presenter: FakePresenter!
    private var clock = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var suppressed = false
    private var escalation = EscalationSettings(maxReminders: 3, intervalMinutes: 15)
    private var scheduler: ReminderScheduler!

    /// Fresh in-memory store + scheduler for each test (XCTest makes a new
    /// instance of this class per test, so state never leaks between them).
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
            shouldSuppress: { [unowned self] in self.suppressed },
            escalationSettings: { [unowned self] in self.escalation }
        )
        scheduler.attach(modelContext: context)
    }

    // MARK: - Helpers

    private func advance(minutes: Double) { clock = clock.addingTimeInterval(minutes * 60) }

    @discardableResult
    private func addRepeating(everyMinutes: Double, dueIn minutes: Double = 0) -> Item {
        let item = Item(title: "Drink water", kind: .repeatingRoutine, intervalSeconds: everyMinutes * 60)
        item.nextFireDate = clock.addingTimeInterval(minutes * 60)
        context.insert(item)
        return item
    }

    private func occurrences() -> [Occurrence] {
        (try? context.fetch(FetchDescriptor<Occurrence>())) ?? []
    }

    /// Nobody answered — the panel auto-collapses but the reminder stays pending.
    private func ignore() { scheduler.collapseWithoutResolving() }

    // MARK: - Firing

    func testDueRoutinePopsTheReminder() throws {
        try makeFixture()
        let item = addRepeating(everyMinutes: 40)
        advance(minutes: 1)
        scheduler.tick()

        XCTAssertEqual(occurrences().count, 1)
        XCTAssertEqual(occurrences().first?.status, .pending)
        XCTAssertEqual(occurrences().first?.remindersSentCount, 1)
        XCTAssertEqual(presenter.liveShown, 1)
        XCTAssertNotNil(scheduler.activeOccurrence)
        // Next one is scheduled from the due time, as an absolute timestamp.
        XCTAssertEqual(item.nextFireDate, clock.addingTimeInterval(-60 + 40 * 60))
    }

    func testNotDueYetDoesNothing() throws {
        try makeFixture()
        addRepeating(everyMinutes: 40, dueIn: 10)
        advance(minutes: 5)
        scheduler.tick()
        XCTAssertEqual(occurrences().count, 0)
        XCTAssertEqual(presenter.liveShown, 0)
    }

    func testGoalsAndPausedRoutinesNeverPop() throws {
        try makeFixture()
        context.insert(Item(title: "Go to Godavari", kind: .goal))
        let paused = addRepeating(everyMinutes: 1)
        paused.isActive = false
        advance(minutes: 10)
        scheduler.tick()
        XCTAssertEqual(occurrences().count, 0)
        XCTAssertEqual(presenter.liveShown, 0)
    }

    // MARK: - Escalation (your 3 pops, 15 minutes apart by default)

    func testUnansweredReminderPopsThreeTimesThenGoesUnfinished() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)       // long interval so only one occurrence is in play
        scheduler.tick()                      // pop 1
        ignore()

        advance(minutes: 14); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 1, "must not re-pop before 15 minutes")

        advance(minutes: 1.1); scheduler.tick() // pop 2 at 15m
        ignore()
        advance(minutes: 15.1); scheduler.tick() // pop 3 at 30m
        ignore()
        XCTAssertEqual(presenter.liveShown, 3)
        XCTAssertEqual(occurrences().first?.status, .pending)

        advance(minutes: 15.1); scheduler.tick() // 45m: gives up
        XCTAssertEqual(presenter.liveShown, 3, "no 4th pop")
        XCTAssertEqual(occurrences().first?.status, .unfinished)
        XCTAssertNil(occurrences().first?.nextEscalationAt)

        advance(minutes: 60); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 3, "stops nagging for good")
    }

    func testCustomEscalationSettingsAreRespected() throws {
        try makeFixture()
        escalation = EscalationSettings(maxReminders: 2, intervalMinutes: 5)
        addRepeating(everyMinutes: 600)
        scheduler.tick(); ignore()                        // pop 1
        advance(minutes: 5.1); scheduler.tick(); ignore() // pop 2
        advance(minutes: 5.1); scheduler.tick()           // out of pops
        XCTAssertEqual(presenter.liveShown, 2)
        XCTAssertEqual(occurrences().first?.status, .unfinished)
    }

    // MARK: - The three buttons

    func testDoneStopsTheNagging() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)
        scheduler.tick()
        scheduler.markDone()
        XCTAssertEqual(occurrences().first?.status, .done)
        XCTAssertNil(scheduler.activeOccurrence)
        advance(minutes: 30); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 1)
    }

    func testSkipStopsTheNagging() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)
        scheduler.tick()
        scheduler.skip()
        XCTAssertEqual(occurrences().first?.status, .skipped)
        advance(minutes: 30); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 1)
    }

    func testSnoozeComesBackInFiveMinutes() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)
        scheduler.tick()
        scheduler.snooze()
        advance(minutes: 4.9); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 1, "not before 5 minutes")
        advance(minutes: 0.2); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 2, "back after 5 minutes")
    }

    func testSnoozeOnTheLastPopStillComesBack() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)
        scheduler.tick(); ignore()                          // pop 1
        advance(minutes: 15.1); scheduler.tick(); ignore()  // pop 2
        advance(minutes: 15.1); scheduler.tick()            // pop 3 (last)
        scheduler.snooze()

        advance(minutes: 5.1); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 4, "a snooze must always re-pop")
        XCTAssertEqual(occurrences().first?.status, .pending)
    }

    // MARK: - Sleep / wake

    func testLongSleepFiresOnceNotABacklog() throws {
        try makeFixture()
        let item = addRepeating(everyMinutes: 40)
        advance(minutes: 5 * 60)               // Mac asleep for 5 hours
        scheduler.tick()                       // what the wake notification triggers
        XCTAssertEqual(occurrences().count, 1, "one catch-up, not 7 stacked reminders")
        XCTAssertEqual(presenter.liveShown, 1)
        XCTAssertEqual(item.nextFireDate, clock.addingTimeInterval(40 * 60),
                       "next one counts from now, not from before the sleep")
    }

    // MARK: - Focus / full screen

    func testSuppressedDoesNotUseUpAnAttempt() throws {
        try makeFixture()
        suppressed = true
        addRepeating(everyMinutes: 600)
        scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 0, "nothing pops during Do Not Disturb / full screen")
        XCTAssertEqual(occurrences().first?.remindersSentCount, 0)

        suppressed = false
        advance(minutes: 1); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 1, "shows once the Focus ends")
        XCTAssertEqual(occurrences().first?.remindersSentCount, 1)
    }

    func testTwoDueAtOnceShowOneAtATime() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)
        let second = Item(title: "Stretch", kind: .repeatingRoutine, intervalSeconds: 600 * 60)
        second.nextFireDate = clock
        context.insert(second)

        scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 1, "never two reminders on screen at once")
        scheduler.markDone()
        advance(minutes: 1); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 2, "the second one gets its turn")
    }
}
