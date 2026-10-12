import XCTest
import SwiftData
@testable import RemindMe

/// Records what the scheduler asked the screen to do, instead of showing windows.
@MainActor
final class FakePresenter: LiveReminderPresenting {
    var liveShown = 0
    var liveDismissed = 0
    var liveSuspended = 0
    var overlayShown = 0
    func presentLiveReminder() { liveShown += 1 }
    func dismissLiveReminder() { liveDismissed += 1 }
    func suspendLiveReminder() { liveSuspended += 1 }
    func presentOverlay() { overlayShown += 1 }
    func dismissOverlay() {}
}

/// The reliability-critical part: firing, nagging, snooze, sleep catch-up and
/// Focus handling, driven by a fake clock so minutes pass instantly.
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
    private func addRepeating(everyMinutes: Double, dueIn minutes: Double = 0, title: String = "Drink water") -> Item {
        let item = Item(title: title, kind: .repeatingRoutine, intervalSeconds: everyMinutes * 60)
        item.nextFireDate = clock.addingTimeInterval(minutes * 60)
        context.insert(item)
        return item
    }

    private func occurrences() -> [Occurrence] {
        (try? context.fetch(FetchDescriptor<Occurrence>())) ?? []
    }

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

    // MARK: - Stays until answered

    func testReminderStaysOnScreenUntilAnswered() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)
        scheduler.tick()
        for _ in 0..<24 { advance(minutes: 5); scheduler.tick() } // two hours, nobody answers
        XCTAssertNotNil(scheduler.activeOccurrence, "never closes on its own")
        XCTAssertEqual(presenter.liveDismissed, 0)
    }

    func testUnansweredReminderNagsInPlaceThenCountsAsUnfinished() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)       // long interval so only one occurrence is in play
        scheduler.tick()                      // shown (1)
        let shown = scheduler.activeOccurrence

        advance(minutes: 14); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 1, "no nag before 15 minutes")

        advance(minutes: 1.1); scheduler.tick() // nag 2 at 15m
        advance(minutes: 15.1); scheduler.tick() // nag 3 at 30m
        XCTAssertEqual(presenter.liveShown, 3)
        XCTAssertEqual(occurrences().first?.remindersSentCount, 3)

        advance(minutes: 15.1); scheduler.tick() // 45m: out of nags
        XCTAssertEqual(occurrences().first?.status, .unfinished, "counts as unfinished for the day")
        XCTAssertEqual(scheduler.activeOccurrence?.id, shown?.id, "but stays on screen to be answered")
        XCTAssertEqual(presenter.liveDismissed, 0)

        advance(minutes: 60); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 3, "and stops nagging")
    }

    func testMoodRisesWithEachNag() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)
        func mood() -> FaceMood {
            FaceMood.forPop(count: scheduler.activeOccurrence!.remindersSentCount, maxPops: escalation.maxReminders)
        }
        scheduler.tick()
        XCTAssertEqual(mood(), .gentle)
        advance(minutes: 15.1); scheduler.tick()
        XCTAssertEqual(mood(), .nudge)
        advance(minutes: 15.1); scheduler.tick()
        XCTAssertEqual(mood(), .urgent)
    }

    func testCustomEscalationSettingsAreRespected() throws {
        try makeFixture()
        escalation = EscalationSettings(maxReminders: 2, intervalMinutes: 5)
        addRepeating(everyMinutes: 600)
        scheduler.tick()                         // 1
        advance(minutes: 5.1); scheduler.tick()  // 2
        advance(minutes: 5.1); scheduler.tick()  // out of nags
        XCTAssertEqual(presenter.liveShown, 2)
        XCTAssertEqual(occurrences().first?.status, .unfinished)
    }

    // MARK: - The three buttons

    func testDoneClosesItAndStopsTheNagging() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)
        scheduler.tick()
        scheduler.markDone()
        XCTAssertEqual(occurrences().first?.status, .done)
        XCTAssertNil(scheduler.activeOccurrence)
        XCTAssertEqual(presenter.liveDismissed, 1)
        advance(minutes: 30); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 1)
    }

    func testSkipClosesItAndStopsTheNagging() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)
        scheduler.tick()
        scheduler.skip()
        XCTAssertEqual(occurrences().first?.status, .skipped)
        XCTAssertEqual(presenter.liveDismissed, 1)
        advance(minutes: 30); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 1)
    }

    func testSnoozeComesBackInFiveMinutes() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)
        scheduler.tick()
        scheduler.snooze()
        XCTAssertNil(scheduler.activeOccurrence)
        advance(minutes: 4.9); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 1, "not before 5 minutes")
        advance(minutes: 0.2); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 2, "back after 5 minutes")
    }

    func testSnoozeOnTheLastNagStillComesBack() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)
        scheduler.tick()                          // 1
        advance(minutes: 15.1); scheduler.tick()  // 2
        advance(minutes: 15.1); scheduler.tick()  // 3 (last)
        scheduler.snooze()

        advance(minutes: 5.1); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 4, "a snooze must always come back")
        XCTAssertEqual(occurrences().first?.status, .pending)
    }

    func testAnsweringAfterItWentUnfinishedStillWorks() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)
        scheduler.tick()
        advance(minutes: 15.1); scheduler.tick()
        advance(minutes: 15.1); scheduler.tick()
        advance(minutes: 15.1); scheduler.tick()
        XCTAssertEqual(occurrences().first?.status, .unfinished)

        scheduler.markDone()
        XCTAssertEqual(occurrences().first?.status, .done, "late Done still counts")
        XCTAssertNil(scheduler.activeOccurrence)
    }

    func testSnoozingAnUnfinishedReminderPutsItBackInPlay() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)
        scheduler.tick()
        advance(minutes: 15.1); scheduler.tick()
        advance(minutes: 15.1); scheduler.tick()
        advance(minutes: 15.1); scheduler.tick()
        scheduler.snooze()
        XCTAssertEqual(occurrences().first?.status, .pending)
        advance(minutes: 5.1); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 4)
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

    func testWaitingReminderTucksAwayDuringFocusAndComesBack() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)
        scheduler.tick()                                   // on screen

        suppressed = true
        scheduler.tick()
        XCTAssertEqual(presenter.liveSuspended, 1, "hidden while the Focus is on")
        XCTAssertTrue(scheduler.isLiveReminderSuspended)
        XCTAssertNotNil(scheduler.activeOccurrence, "hidden, not dropped")

        advance(minutes: 15.1); scheduler.tick()
        XCTAssertEqual(occurrences().first?.remindersSentCount, 1, "no nag spent during the Focus")

        suppressed = false
        scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 2, "back when the Focus ends")
        XCTAssertFalse(scheduler.isLiveReminderSuspended)

        advance(minutes: 1); scheduler.tick()
        XCTAssertEqual(occurrences().first?.remindersSentCount, 2, "then the delayed nag happens")
    }

    // MARK: - More than one due

    func testTwoDueAtOnceShowOneAtATime() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600)
        addRepeating(everyMinutes: 600, title: "Stretch")

        scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 1, "never two reminders on screen at once")
        scheduler.markDone()
        advance(minutes: 1); scheduler.tick()
        XCTAssertEqual(presenter.liveShown, 2, "the second one gets its turn")
    }

    func testNextReminderWaitsWhileOneIsUnanswered() throws {
        try makeFixture()
        addRepeating(everyMinutes: 600, title: "Drink water")
        addRepeating(everyMinutes: 600, dueIn: 10, title: "Stretch")
        scheduler.tick()
        let first = scheduler.activeOccurrence
        for _ in 0..<8 { advance(minutes: 5); scheduler.tick() }
        XCTAssertEqual(scheduler.activeOccurrence?.id, first?.id, "Stretch waits its turn")

        scheduler.markDone()
        advance(minutes: 1); scheduler.tick()
        XCTAssertEqual(scheduler.activeOccurrence?.item?.title, "Stretch")
    }
}
