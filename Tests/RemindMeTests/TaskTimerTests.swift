import XCTest
@testable import RemindMe

/// "choosing music within 30 min" starts a timer. At zero it asks; no answer for
/// a minute turns it red. Reminder phrases never become timers.
final class TaskTimerTests: XCTestCase {
    func testTaskPhrasesBecomeTimers() {
        let cases: [(String, String, Double, String?)] = [
            ("choosing music within 30 min", "Choosing music", 1800, "Music"),
            ("finish color grading with in 30 min", "Finish color grading", 1800, "Grading"),
            ("edit 30 min", "Edit", 1800, "Editing"),
            ("file manage within 10 min", "File manage", 600, "Files"),
        ]
        for (text, title, seconds, category) in cases {
            let request = TimerRequest.parse(text)
            XCTAssertEqual(request?.title, title, text)
            XCTAssertEqual(request?.seconds, seconds, text)
            XCTAssertEqual(request?.category, category, text)
        }
    }

    func testDrinkWaterWithinFortyMinutesIsATimer() {
        let parsed = ItemParser.parse("drink water within 40 minute", now: .now)
        XCTAssertEqual(parsed.timer?.seconds, 2400)
        XCTAssertEqual(parsed.timer?.title, "Drink water")
    }

    func testReminderPhrasesAreNotTimers() {
        for text in ["in 2 hours", "remind me in 20 min to check the export",
                     "drink water every 40 minutes", "Nov 5 at 10am", "tomorrow 3pm", "pay rent on the 1st"] {
            XCTAssertNil(TimerRequest.parse(text), text)
        }
    }

    func testParserReturnsATimerForATaskPhrase() {
        let parsed = ItemParser.parse("choosing music within 30 min", now: .now)
        XCTAssertEqual(parsed.timer?.seconds, 1800)
        XCTAssertEqual(parsed.type, .reminder)
        XCTAssertNil(ItemParser.parse("in 2 hours", now: .now).timer)
    }

    func testCountsDownThenAsksThenTurnsRed() {
        var timers = TaskTimers()
        let t0 = Date(timeIntervalSince1970: 1_000)
        timers.start(title: "Choosing music", category: nil, seconds: 1800, at: t0)
        let id = timers.entries[0].id
        XCTAssertTrue(timers.advance(now: t0.addingTimeInterval(1799)).isEmpty)
        XCTAssertEqual(timers.advance(now: t0.addingTimeInterval(1800)).asking.map(\.id), [id])
        XCTAssertTrue(timers.advance(now: t0.addingTimeInterval(1830)).isEmpty, "still inside the minute to answer")
        XCTAssertEqual(timers.advance(now: t0.addingTimeInterval(1860)).overdue.map(\.id), [id])
        XCTAssertEqual(timers.entries[0].state, .overdue)
        timers.markDone(id)
        XCTAssertTrue(timers.open.isEmpty)
    }

    func testNotYetKeepsItOpenInRed() {
        var timers = TaskTimers()
        let t0 = Date(timeIntervalSince1970: 1_000)
        timers.start(title: "Edit", category: "Editing", seconds: 60, at: t0)
        let id = timers.entries[0].id
        _ = timers.advance(now: t0.addingTimeInterval(60))
        timers.notYet(id)
        XCTAssertEqual(timers.open.map(\.id), [id])
        XCTAssertEqual(timers.entries[0].state, .overdue)
    }

    func testClockFormat() {
        XCTAssertEqual(TaskTimers.clock(0), "0:00")
        XCTAssertEqual(TaskTimers.clock(65), "1:05")
        XCTAssertEqual(TaskTimers.clock(3725), "1:02:05")
        XCTAssertEqual(TaskTimers.clock(-3), "0:00")
    }

    func testTimersRunOneAfterAnother() {
        var timers = TaskTimers()
        let t0 = Date(timeIntervalSince1970: 1_000)
        timers.start(title: "Select sound", category: nil, seconds: 1200, at: t0)
        timers.start(title: "Edit video", category: "Editing", seconds: 1200, at: t0)
        let first = timers.entries.last!
        let second = timers.entries.first!
        XCTAssertEqual(first.state, .running)
        XCTAssertEqual(second.state, .queued)
        XCTAssertEqual(timers.current?.id, first.id)

        let later = t0.addingTimeInterval(1200)
        _ = timers.advance(now: later)
        timers.markDone(first.id, now: later)
        XCTAssertEqual(timers.current?.id, second.id, "the next one is on the notch now")
        XCTAssertEqual(timers.entries.first { $0.id == second.id }?.startedAt, later)
        XCTAssertEqual(timers.entries.first { $0.id == second.id }?.state, .running)
    }

    func testOneLineSplitsIntoSeparateTimers() {
        let parts = TimerRequest.parseAll("edit song 2 min , write song 3 min")
        XCTAssertEqual(parts.map(\.seconds), [120, 180])
        XCTAssertEqual(TimerRequest.parseAll("select sound within 20 min. edit video 20 min").count, 2)
        XCTAssertEqual(TimerRequest.parseAll("color grade 20 min - export 10 min and rest 5 min").count, 3)
    }

    func testSplittingKeepsDecimalsAndSingleTasksWhole() {
        XCTAssertEqual(TimerRequest.parseAll("sound and light 10 min"), [])
        XCTAssertEqual(TimerRequest.parseAll("edit 1.5 min").count, 0)
        XCTAssertEqual(TimerRequest.parseAll("edit video 1.5 min, write 2 min").map(\.seconds), [90, 120])
    }

    func testSkipStartsTheNextTimerWithoutCountingItDone() {
        var timers = TaskTimers()
        let t0 = Date(timeIntervalSince1970: 1_000)
        timers.start(title: "Drink water", category: nil, seconds: 60, at: t0)
        timers.start(title: "Edit", category: nil, seconds: 60, at: t0)
        let first = timers.entries.last!
        let second = timers.entries.first!
        timers.markDone(first.id, now: t0.addingTimeInterval(60))
        XCTAssertEqual(timers.current?.id, second.id)
    }
}
