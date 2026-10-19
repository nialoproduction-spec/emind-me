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
        XCTAssertEqual(p.kindLabel, "Reminder")
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

    func testLastTenMinutesHeadsUpForALongWorkStretch() {
        let state = BreakCycleState.started(config, at: t0)
        let at29 = t0.addingTimeInterval(29 * 60)
        XCTAssertNil(state.dueMilestone(at: at29, shown: []))
        let at30 = t0.addingTimeInterval(30 * 60)
        XCTAssertEqual(state.dueMilestone(at: at30, shown: []), .lastTen)
        XCTAssertNil(state.dueMilestone(at: at30, shown: [.lastTen]), "only once per phase")
    }

    func testLastSecondsStartsAtTen() {
        let state = BreakCycleState.started(config, at: t0)
        let at11 = t0.addingTimeInterval(40 * 60 - 11)
        XCTAssertNil(state.dueMilestone(at: at11, shown: [.lastTen]))
        let at10 = t0.addingTimeInterval(40 * 60 - 10)
        XCTAssertEqual(state.dueMilestone(at: at10, shown: [.lastTen]), .lastSeconds)
    }

    func testShortCyclesSkipLastTenMinutes() {
        let state = BreakCycleState.started(BreakCycleConfig(workMinutes: 5, breakMinutes: 1), at: t0)
        XCTAssertNil(state.dueMilestone(at: t0.addingTimeInterval(60), shown: []))
        XCTAssertEqual(state.dueMilestone(at: t0.addingTimeInterval(5 * 60 - 3), shown: []), .lastSeconds)
    }

    func testBreaksNeverGetALastTenMinutesPopup() {
        var state = BreakCycleState.started(BreakCycleConfig(workMinutes: 40, breakMinutes: 30), at: t0)
        state.advance(now: t0.addingTimeInterval(40 * 60))
        let midBreak = t0.addingTimeInterval(40 * 60 + 25 * 60)
        XCTAssertNil(state.dueMilestone(at: midBreak, shown: []))
    }
}

@MainActor
final class BreakCycleManagerTests: XCTestCase {
    private var now = Date(timeIntervalSinceReferenceDate: 2_000_000)
    /// Every popup the manager asked for; nil = "put the popup away".
    private var popups: [NoticeContent?] = []

    private var titles: [String] { popups.compactMap { $0?.title } }

    private func makeManager(defaults: UserDefaults? = nil) -> BreakCycleManager {
        BreakCycleManager(
            defaults: defaults ?? UserDefaults(suiteName: "BreakCycleTests-\(UUID().uuidString)")!,
            now: { [unowned self] in self.now },
            notice: { [unowned self] in self.popups.append($0) }
        )
    }

    func testStartingShowsHowLongToGoWithACountdown() throws {
        let manager = makeManager()
        manager.startCycle(BreakCycleConfig(workMinutes: 40, breakMinutes: 10))
        XCTAssertEqual(manager.menuBarTitle, "40:00")
        let popup = try XCTUnwrap(popups.last ?? nil)
        XCTAssertEqual(popup.title, "40 minutes to go")
        XCTAssertEqual(popup.countdownTo, now.addingTimeInterval(40 * 60))
        XCTAssertFalse(popup.sticky)
    }

    func testFullCycleWithPopupsAtEveryMoment() throws {
        let manager = makeManager()
        manager.startCycle(BreakCycleConfig(workMinutes: 40, breakMinutes: 10))

        now.addTimeInterval(20 * 60)
        manager.tick()
        XCTAssertEqual(titles, ["40 minutes to go"], "quiet in the middle")

        now.addTimeInterval(10 * 60) // 10 minutes left
        manager.tick()
        XCTAssertEqual(titles.last, "Last 10 minutes to go")

        now.addTimeInterval(10 * 60 - 10) // 10 seconds left
        manager.tick()
        let last = try XCTUnwrap(popups.last ?? nil)
        XCTAssertEqual(last.title, "Break time is almost here")
        XCTAssertTrue(last.sticky, "the last seconds stay on screen, counting")
        manager.tick()
        XCTAssertEqual(popups.count, 3, "and it isn't re-shown every tick")

        now.addTimeInterval(10)
        manager.tick()
        let breakPopup = try XCTUnwrap(popups.last ?? nil)
        XCTAssertEqual(breakPopup.title, "Time for a break")
        XCTAssertEqual(breakPopup.detail, "Rest for 10 minutes.")
        XCTAssertNotNil(breakPopup.face, "a face, not an app icon")
        XCTAssertEqual(manager.menuBarTitle, "Break 10:00")

        now.addTimeInterval(10 * 60)
        manager.tick()
        XCTAssertEqual(titles.last, "Break over · 40 minutes to go")
        XCTAssertEqual(manager.state?.phase, .work, "and the next work stretch has begun")
    }

    func testOneMinuteTestCycle() throws {
        let manager = makeManager()
        manager.startCycle(BreakCycleConfig(workMinutes: 1, breakMinutes: 1))
        XCTAssertEqual(titles, ["1 minute to go"])
        now.addTimeInterval(50)
        manager.tick()
        XCTAssertEqual(titles.last, "Break time is almost here")
        now.addTimeInterval(10)
        manager.tick()
        let breakPopup = try XCTUnwrap(popups.last ?? nil)
        XCTAssertEqual(breakPopup.detail, "Rest for 1 minute.", "singular, not '1 minutes'")
    }

    func testSleepPausesTheCycle() {
        let manager = makeManager()
        manager.startCycle(BreakCycleConfig(workMinutes: 40, breakMinutes: 10))
        now.addTimeInterval(10 * 60)
        manager.willSleep()
        now.addTimeInterval(3 * 3600) // asleep for three hours
        manager.tick()
        XCTAssertEqual(titles, ["40 minutes to go"], "nothing pops up while asleep")

        manager.didWake()
        XCTAssertEqual(manager.menuBarTitle, "30:00", "sleep doesn't count as work")
        XCTAssertEqual(manager.state?.phase, .work)
    }

    func testStopClearsTheMenuBarThePopupAndTheSavedCycle() {
        let defaults = UserDefaults(suiteName: "BreakCycleTests-\(UUID().uuidString)")!
        let manager = makeManager(defaults: defaults)
        manager.startCycle(BreakCycleConfig(workMinutes: 40, breakMinutes: 10))
        manager.stop()
        XCTAssertFalse(manager.isRunning)
        XCTAssertEqual(manager.menuBarTitle, "")
        XCTAssertNil(popups.last ?? NoticeContent(title: "still showing"), "the popup is put away")

        XCTAssertFalse(makeManager(defaults: defaults).isRunning)
    }

    func testARunningCycleSurvivesARestart() {
        let defaults = UserDefaults(suiteName: "BreakCycleTests-\(UUID().uuidString)")!
        let first = makeManager(defaults: defaults)
        first.startCycle(BreakCycleConfig(workMinutes: 40, breakMinutes: 10))
        now.addTimeInterval(5 * 60)
        XCTAssertEqual(makeManager(defaults: defaults).menuBarTitle, "35:00")
    }
}
