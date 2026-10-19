import XCTest
@testable import RemindMe

/// The break timer: parsing the sentence, the phase maths, and the manager's
/// beeps and sleep handling, all with an injected clock (no real timers,
/// sounds or notifications).
final class BreakCycleParserTests: XCTestCase {

    func testRestEvery40MinAndTake10MinBreak() {
        let p = ItemParser.parse("rest every 40 min and take a 10 min break")
        XCTAssertEqual(p.breakCycle, BreakCycleConfig(workMinutes: 40, breakMinutes: 10))
        XCTAssertEqual(p.kindLabel, "Break timer")
        XCTAssertEqual(p.title, "Rest every 40 min")
        XCTAssertEqual(p.detailLine, "10 min break · repeats until you stop it")
    }

    func testWordNumbersDoNotLeakIntoEachOther() {
        let p = ItemParser.parse("rest every forty minutes and take a ten minute break")
        XCTAssertEqual(p.breakCycle, BreakCycleConfig(workMinutes: 40, breakMinutes: 10))
    }

    func testBreakLengthAfterTheWord() {
        let p = ItemParser.parse("rest every 40 min, break for 10 minutes")
        XCTAssertEqual(p.breakCycle, BreakCycleConfig(workMinutes: 40, breakMinutes: 10))
    }

    func testHourlyWorkWithHyphenatedBreak() {
        let p = ItemParser.parse("stretch every hour and take a 5-minute break")
        XCTAssertEqual(p.breakCycle, BreakCycleConfig(workMinutes: 60, breakMinutes: 5))
    }

    func testPlainRoutineIsNotABreakTimer() {
        let p = ItemParser.parse("drink water every 40 minutes")
        XCTAssertNil(p.breakCycle)
        XCTAssertEqual(p.kind, .repeatingRoutine)
        XCTAssertEqual(p.kindLabel, "Routine")
    }

    func testBreakWithoutAnIntervalIsNotABreakTimer() {
        XCTAssertNil(ItemParser.parse("take a 10 min break").breakCycle)
    }
}

final class BreakCycleStateTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private let config = BreakCycleConfig(workMinutes: 40, breakMinutes: 10)

    func testWorkPhaseEndsAfterFortyMinutes() {
        var state = BreakCycleState.started(config, at: t0)
        XCTAssertNil(state.advance(now: t0.addingTimeInterval(40 * 60 - 1)))
        XCTAssertEqual(state.phase, .work)
        XCTAssertEqual(state.advance(now: t0.addingTimeInterval(40 * 60)), .breakStarted)
        XCTAssertEqual(state.phase, .onBreak)
    }

    func testBreakLastsTenMinutesThenWorkStartsAgain() {
        var state = BreakCycleState.started(config, at: t0)
        let breakStart = t0.addingTimeInterval(40 * 60)
        state.advance(now: breakStart)
        XCTAssertEqual(state.remaining(at: breakStart), 10 * 60)
        XCTAssertNil(state.advance(now: breakStart.addingTimeInterval(10 * 60 - 1)))
        XCTAssertEqual(state.advance(now: breakStart.addingTimeInterval(10 * 60)), .breakEnded)
        XCTAssertEqual(state.phase, .work, "it loops until stopped")
        XCTAssertEqual(state.remaining(at: breakStart.addingTimeInterval(10 * 60)), 40 * 60)
    }

    func testLongGapCostsOneSwitchNotABacklog() {
        var state = BreakCycleState.started(config, at: t0)
        let late = t0.addingTimeInterval(5 * 3600)
        XCTAssertEqual(state.advance(now: late), .breakStarted)
        XCTAssertNil(state.advance(now: late), "a second call at the same moment does nothing")
        XCTAssertEqual(state.remaining(at: late), 10 * 60)
    }

    func testSleepShiftPushesTheEndBack() {
        var state = BreakCycleState.started(config, at: t0)
        state.shiftForward(by: 300)
        XCTAssertEqual(state.remaining(at: t0), 40 * 60 + 300)
        state.shiftForward(by: -50)
        XCTAssertEqual(state.remaining(at: t0), 40 * 60 + 300, "never shifts backwards")
    }

    func testClockStringAndMenuBarTitle() {
        XCTAssertEqual(BreakCycleState.clockString(600), "10:00")
        XCTAssertEqual(BreakCycleState.clockString(582), "9:42")
        XCTAssertEqual(BreakCycleState.clockString(0.2), "0:01")
        XCTAssertEqual(BreakCycleState.clockString(0), "0:00")

        var state = BreakCycleState.started(config, at: t0)
        XCTAssertEqual(state.menuBarTitle(at: t0), "40:00")
        let breakStart = t0.addingTimeInterval(40 * 60)
        state.advance(now: breakStart)
        XCTAssertEqual(state.menuBarTitle(at: breakStart.addingTimeInterval(18)), "Break 9:42")
    }
}

@MainActor
final class BreakCycleManagerTests: XCTestCase {
    private var now = Date(timeIntervalSinceReferenceDate: 2_000_000)
    private var beeps: [Int] = []
    private var notices: [String] = []

    private func makeManager() -> BreakCycleManager {
        let defaults = UserDefaults(suiteName: "BreakCycleTests-\(UUID().uuidString)")!
        return BreakCycleManager(
            defaults: defaults,
            now: { [unowned self] in self.now },
            beep: { [unowned self] count in self.beeps.append(count) },
            notify: { [unowned self] title, _ in self.notices.append(title) }
        )
    }

    func testFullCycleBeepsAtBreakStartAndAtBreakEnd() {
        let manager = makeManager()
        manager.startCycle(BreakCycleConfig(workMinutes: 40, breakMinutes: 10))
        XCTAssertEqual(manager.menuBarTitle, "40:00")

        now.addTimeInterval(40 * 60)
        manager.tick()
        XCTAssertEqual(beeps, [1])
        XCTAssertEqual(notices, ["Time for a break"])
        XCTAssertEqual(manager.menuBarTitle, "Break 10:00")

        now.addTimeInterval(60)
        manager.tick()
        XCTAssertEqual(manager.menuBarTitle, "Break 9:00")

        now.addTimeInterval(9 * 60)
        manager.tick()
        XCTAssertEqual(beeps, [1, 3], "a longer beep when the break is over")
        XCTAssertEqual(notices, ["Time for a break", "Break over"])
        XCTAssertEqual(manager.state?.phase, .work, "and the next work stretch has begun")
    }

    func testSleepPausesTheCycle() {
        let manager = makeManager()
        manager.startCycle(BreakCycleConfig(workMinutes: 40, breakMinutes: 10))
        now.addTimeInterval(10 * 60)
        manager.willSleep()
        now.addTimeInterval(3 * 3600) // asleep for three hours
        manager.tick()
        XCTAssertTrue(beeps.isEmpty, "nothing fires while asleep")

        manager.didWake()
        XCTAssertTrue(beeps.isEmpty, "sleep doesn't count as work")
        XCTAssertEqual(manager.menuBarTitle, "30:00")
        XCTAssertEqual(manager.state?.phase, .work)
    }

    func testStopClearsTheMenuBarAndTheSavedCycle() {
        let defaults = UserDefaults(suiteName: "BreakCycleTests-\(UUID().uuidString)")!
        let manager = BreakCycleManager(defaults: defaults, now: { [unowned self] in self.now },
                                        beep: { _ in }, notify: { _, _ in })
        manager.startCycle(BreakCycleConfig(workMinutes: 40, breakMinutes: 10))
        manager.stop()
        XCTAssertFalse(manager.isRunning)
        XCTAssertEqual(manager.menuBarTitle, "")

        let reloaded = BreakCycleManager(defaults: defaults, now: { [unowned self] in self.now },
                                         beep: { _ in }, notify: { _, _ in })
        XCTAssertFalse(reloaded.isRunning)
    }

    func testARunningCycleSurvivesARestart() {
        let defaults = UserDefaults(suiteName: "BreakCycleTests-\(UUID().uuidString)")!
        let first = BreakCycleManager(defaults: defaults, now: { [unowned self] in self.now },
                                      beep: { _ in }, notify: { _, _ in })
        first.startCycle(BreakCycleConfig(workMinutes: 40, breakMinutes: 10))
        now.addTimeInterval(5 * 60)

        let second = BreakCycleManager(defaults: defaults, now: { [unowned self] in self.now },
                                       beep: { _ in }, notify: { _, _ in })
        XCTAssertEqual(second.menuBarTitle, "35:00")
    }
}
