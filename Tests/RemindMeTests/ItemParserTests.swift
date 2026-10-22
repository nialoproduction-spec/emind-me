import XCTest
@testable import RemindMe

/// The natural-language parser: does free text land in the right kind,
/// with the right schedule and a clean title?
final class ItemParserTests: XCTestCase {

    // MARK: - Your own examples from the spec

    func testDrinkWaterEveryFortyMinutesWords() {
        let p = ItemParser.parse("drink water every forty minutes")
        XCTAssertEqual(p.kind, .repeatingRoutine)
        XCTAssertEqual(p.intervalSeconds, 40 * 60)
        XCTAssertEqual(p.title, "Drink water")
        XCTAssertEqual(p.detailLine, "every 40 minutes")
        XCTAssertEqual(p.kindLabel, "Reminder")
    }

    func testDrinkWaterEvery40MinutesDigits() {
        let p = ItemParser.parse("drink water every 40 minutes")
        XCTAssertEqual(p.kind, .repeatingRoutine)
        XCTAssertEqual(p.intervalSeconds, 40 * 60)
        XCTAssertEqual(p.title, "Drink water")
    }

    func testWalkAtFourAMEveryDay() {
        let p = ItemParser.parse("walk at four a.m. every day")
        XCTAssertEqual(p.kind, .scheduledRoutine)
        XCTAssertEqual(p.hour, 4)
        XCTAssertEqual(p.minute, 0)
        XCTAssertTrue(p.weekdays.isEmpty, "every day = no weekday filter")
        XCTAssertEqual(p.title, "Walk")
    }

    func testReadABookAtSevenAM_DefaultsToDaily() {
        let p = ItemParser.parse("read a book at seven a.m.")
        XCTAssertEqual(p.kind, .scheduledRoutine)
        XCTAssertEqual(p.hour, 7)
        XCTAssertEqual(p.minute, 0)
        XCTAssertTrue(p.weekdays.isEmpty)
        XCTAssertEqual(p.title, "Read a book")
        XCTAssertTrue(p.detailLine.hasSuffix("Daily"), p.detailLine)
    }

    func testGoToGodavariIsAGoal() {
        let p = ItemParser.parse("go to Godavari")
        XCTAssertEqual(p.kind, .goal)
        XCTAssertNil(p.intervalSeconds)
        XCTAssertNil(p.hour)
        XCTAssertNil(p.targetDate)
        XCTAssertEqual(p.title, "Go to Godavari")
        XCTAssertEqual(p.kindLabel, "Goal")
    }

    // MARK: - Times

    func test24HourClock() {
        let p = ItemParser.parse("meeting at 16:30")
        XCTAssertEqual(p.kind, .scheduledRoutine, "24-hour times must not fall through to a goal")
        XCTAssertEqual(p.hour, 16)
        XCTAssertEqual(p.minute, 30)
        XCTAssertEqual(p.title, "Meeting")
    }

    func testPMWithMinutes() {
        let p = ItemParser.parse("call mom at 4:30pm")
        XCTAssertEqual(p.hour, 16)
        XCTAssertEqual(p.minute, 30)
        XCTAssertEqual(p.title, "Call mom")
    }

    func testTimeWithoutAt() {
        let wife = ItemParser.parse("remind me to msg wife every 6pm")
        XCTAssertEqual(wife.kind, .scheduledRoutine, "every 6pm = every day at 6 PM, not a goal")
        XCTAssertEqual(wife.hour, 18)
        XCTAssertEqual(wife.minute, 0)
        XCTAssertEqual(wife.title, "Msg wife")
        XCTAssertTrue(wife.weekdays.isEmpty, "every day")

        let call = ItemParser.parse("call mom 6:30 pm")
        XCTAssertEqual(call.hour, 18)
        XCTAssertEqual(call.minute, 30)
        XCTAssertEqual(call.title, "Call mom")

        let standup = ItemParser.parse("standup every weekday 9.15am")
        XCTAssertEqual(standup.hour, 9)
        XCTAssertEqual(standup.minute, 15)
        XCTAssertEqual(standup.weekdays, [2, 3, 4, 5, 6])
        XCTAssertEqual(standup.title, "Standup")

        XCTAssertEqual(ItemParser.parse("take pills 21:00").hour, 21)
        XCTAssertEqual(ItemParser.parse("msg wife each six pm").hour, 18)
        XCTAssertEqual(ItemParser.parse("evry 6pm stretch").title, "Stretch", "typo of every too")

        // Plain numbers aren't times.
        XCTAssertNil(ItemParser.parse("drink 3 glasses a day").hour)
        XCTAssertNil(ItemParser.parse("read 2 chapters").hour)
        XCTAssertNil(ItemParser.parse("finish draft by 21.10").hour, "a date, not a time")
        XCTAssertEqual(ItemParser.parse("drink water every 40 min").intervalSeconds, 2400, "intervals unchanged")
    }

    func testTwelveAMIsMidnightAndTwelvePMIsNoon() {
        XCTAssertEqual(ItemParser.parse("backup at 12am").hour, 0)
        XCTAssertEqual(ItemParser.parse("lunch at 12pm").hour, 12)
    }

    func testNoonWord() {
        let p = ItemParser.parse("lunch at noon")
        XCTAssertEqual(p.kind, .scheduledRoutine)
        XCTAssertEqual(p.hour, 12)
        XCTAssertEqual(p.title, "Lunch")
    }

    func testInvalidMinuteIsNotATime() {
        let p = ItemParser.parse("thing at 9:75")
        XCTAssertNotEqual(p.hour, 9, "9:75 is not a real time")
    }

    // MARK: - Weekdays

    func testSpecificWeekdays() {
        let p = ItemParser.parse("gym at 6pm on mondays and wednesdays")
        XCTAssertEqual(p.kind, .scheduledRoutine)
        XCTAssertEqual(p.hour, 18)
        XCTAssertEqual(p.weekdays, [2, 4])
        XCTAssertEqual(p.title, "Gym")
    }

    func testWeekdaysKeyword() {
        let p = ItemParser.parse("standup at 10am weekdays")
        XCTAssertEqual(p.weekdays, [2, 3, 4, 5, 6])
    }

    func testWeddingIsNotWednesday() {
        // "wedding" must not be read as Wednesday — this app's owner edits them.
        let p = ItemParser.parse("export wedding film at 9pm")
        XCTAssertTrue(p.weekdays.isEmpty)
        XCTAssertEqual(p.title, "Export wedding film")
    }

    // MARK: - Intervals

    func testEveryHourWithoutNumber() {
        let p = ItemParser.parse("stretch every hour")
        XCTAssertEqual(p.kind, .repeatingRoutine)
        XCTAssertEqual(p.intervalSeconds, 3600)
        XCTAssertEqual(p.title, "Stretch")
    }

    func testEveryHalfHour() {
        let p = ItemParser.parse("every half hour stand up")
        XCTAssertEqual(p.intervalSeconds, 1800)
        XCTAssertEqual(p.title, "Stand up")
    }

    func testHyphenatedNumberWords() {
        XCTAssertEqual(ItemParser.parse("blink every twenty-five minutes").intervalSeconds, 25 * 60)
    }

    func testEveryTwoDaysReadsAsDays() {
        let p = ItemParser.parse("water plants every 2 days")
        XCTAssertEqual(p.intervalSeconds, 2 * 86400)
        XCTAssertEqual(p.detailLine, "every 2 days")
        XCTAssertEqual(p.title, "Water plants")
    }

    func testEveryDayAloneIsNotAnInterval() {
        // "every day" with a time is a daily *schedule*, not a 24h interval.
        let p = ItemParser.parse("meditate every day at 6am")
        XCTAssertEqual(p.kind, .scheduledRoutine)
        XCTAssertNil(p.intervalSeconds)
        XCTAssertEqual(p.hour, 6)
    }

    // MARK: - Goals

    func testGoalWithTargetDate() {
        let p = ItemParser.parse("pay rent by friday")
        XCTAssertEqual(p.kind, .goal)
        XCTAssertNotNil(p.targetDate)
        XCTAssertEqual(p.title, "Pay rent")
    }

    func testEmptyInput() {
        let p = ItemParser.parse("   ")
        XCTAssertEqual(p.kind, .goal)
        XCTAssertEqual(p.title, "Untitled")
    }

    // MARK: - Duration wording shown in the confirmation

    func testDurationStrings() {
        XCTAssertEqual(Item.durationString(60), "1 minute")
        XCTAssertEqual(Item.durationString(40 * 60), "40 minutes")
        XCTAssertEqual(Item.durationString(3600), "1 hour")
        XCTAssertEqual(Item.durationString(90 * 60), "90 minutes")
        XCTAssertEqual(Item.durationString(86400), "1 day")
        XCTAssertEqual(Item.durationString(3 * 86400), "3 days")
        XCTAssertEqual(Item.durationString(604800), "1 week")
    }

    // MARK: - Categories from hashtags

    func testHashtagSetsTheCategoryAndIsRemoved() {
        let p = ItemParser.parse("drink water every 40 minutes #health")
        XCTAssertEqual(p.category, "Health")
        XCTAssertEqual(p.kind, .repeatingRoutine)
        XCTAssertEqual(p.intervalSeconds, 40 * 60)
        XCTAssertEqual(p.title, "Drink water")
    }

    func testHashtagAtTheStartAndFirstTagWins() {
        let p = ItemParser.parse("#WORK #home standup at 9:30am on weekdays")
        XCTAssertEqual(p.category, "Work")
        XCTAssertEqual(p.kind, .scheduledRoutine)
        XCTAssertEqual(p.hour, 9)
        XCTAssertEqual(p.minute, 30)
        XCTAssertFalse(p.title.contains("#"))
    }

    func testNoHashtagNoCategory() {
        XCTAssertNil(ItemParser.parse("walk at 4am every day").category)
    }

    func testNumberSignIsNotATag() {
        let p = ItemParser.parse("clean room #4")
        XCTAssertNil(p.category)
    }

    func testItemCarriesTheCategory() {
        let item = Item(from: ItemParser.parse("go to Godavari #travel"))
        XCTAssertEqual(item.category, "Travel")
        XCTAssertEqual(item.kind, .goal)
    }

    // MARK: - Dates: one-time, monthly, yearly, deadlines

    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// Wed 21 Oct 2026, 11:36 PM.
    private var now: Date { utc.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 23, minute: 36))! }

    private func parts(_ date: Date?) -> DateComponents {
        utc.dateComponents([.year, .month, .day, .hour, .minute], from: date ?? .distantPast)
    }

    func testOneTimeReminders() throws {
        let tomorrow = ItemParser.parse("call client tomorrow 3pm", now: now, calendar: utc)
        XCTAssertEqual(tomorrow.kind, .scheduledRoutine)
        XCTAssertEqual(tomorrow.title, "Call client")
        let t = parts(tomorrow.onceAt)
        XCTAssertEqual([t.month, t.day, t.hour, t.minute], [10, 22, 15, 0], "fires once, tomorrow at 3 PM")
        XCTAssertEqual(tomorrow.type, .reminder)

        let nov = ItemParser.parse("call bank Nov 5 at 10am", now: now, calendar: utc)
        let n = parts(nov.onceAt)
        XCTAssertEqual([n.year, n.month, n.day, n.hour], [2026, 11, 5, 10])
        XCTAssertEqual(nov.title, "Call bank")

        let soon = ItemParser.parse("remind me to check the render in 2 hours", now: now, calendar: utc)
        XCTAssertEqual(soon.onceAt, now.addingTimeInterval(7200))
        XCTAssertEqual(soon.title, "Check the render")
        XCTAssertEqual(ItemParser.parse("stretch in half an hour", now: now, calendar: utc).onceAt,
                       now.addingTimeInterval(1800))
        XCTAssertEqual(ItemParser.parse("tea in 20m", now: now, calendar: utc).onceAt, now.addingTimeInterval(1200))

        let past = ItemParser.parse("pay fees Jan 3 at 9am", now: now, calendar: utc)
        XCTAssertEqual(parts(past.onceAt).year, 2027, "a date that's gone this year means next year")

        let asked = ItemParser.parse("remind me to call the bank tomorrow", now: now, calendar: utc)
        XCTAssertEqual(parts(asked.onceAt).hour, 9, "remind me + a day: 9 AM that day")
        XCTAssertEqual(asked.title, "Call the bank")

        XCTAssertEqual(ItemParser.parse("finish the edit tomorrow", now: now, calendar: utc).kind, .goal,
                       "a day with no time is still a goal")
        XCTAssertEqual(ItemParser.parse("msg wife every 6pm", now: now, calendar: utc).onceAt, nil, "daily stays daily")
    }

    func testMonthlyAndYearly() {
        let rent = ItemParser.parse("pay rent on the 1st", now: now, calendar: utc)
        XCTAssertEqual(rent.kind, .scheduledRoutine)
        XCTAssertEqual(rent.monthDay, 1)
        XCTAssertNil(rent.yearMonth)
        XCTAssertEqual(rent.hour, 9)
        XCTAssertEqual(rent.title, "Pay rent")

        let bills = ItemParser.parse("pay bills every 15th at 7pm", now: now, calendar: utc)
        XCTAssertEqual(bills.monthDay, 15)
        XCTAssertEqual(bills.hour, 19)

        let backup = ItemParser.parse("back up the drives every month", now: now, calendar: utc)
        XCTAssertEqual(backup.monthDay, 21, "every month, from today")

        let anniversary = ItemParser.parse("anniversary every Mar 12", now: now, calendar: utc)
        XCTAssertEqual(anniversary.monthDay, 12)
        XCTAssertEqual(anniversary.yearMonth, 3)
        XCTAssertEqual(anniversary.title, "Anniversary")

        let birthday = ItemParser.parse("mom's birthday Mar 12", now: now, calendar: utc)
        XCTAssertEqual(birthday.yearMonth, 3, "birthdays come round every year")

        XCTAssertNil(ItemParser.parse("send 2nd draft to client", now: now, calendar: utc).monthDay,
                     "an ordinal on its own isn't a date")
        XCTAssertNil(ItemParser.parse("I may 5 times", now: now, calendar: utc).onceAt, "may, the word")
    }

    func testDeadlines() {
        let teaser = ItemParser.parse("Sharma teaser due Nov 10", now: now, calendar: utc)
        XCTAssertEqual(teaser.kind, .scheduledRoutine)
        XCTAssertEqual(teaser.title, "Sharma teaser")
        let d = parts(teaser.dueDate)
        XCTAssertEqual([d.month, d.day], [11, 10])
        XCTAssertEqual(teaser.hour, 10, "nudges at 10 AM")
        XCTAssertTrue(teaser.detailLine.contains("nudges 7, 3, 1 day before"))

        let item = Item(from: teaser, now: now)
        XCTAssertEqual(item.style, .justRemind, "a deadline nudges with the popup")
        XCTAssertEqual(item.repeatKind, .deadline)
    }

    func testMonthlyDayClampsAndDeadlineNudges() {
        let jan31 = utc.date(from: DateComponents(year: 2027, month: 1, day: 31, hour: 10))!
        let next = Item.nextMonthly(day: 31, month: nil, hour: 9, minute: 0, after: jan31, calendar: utc)
        XCTAssertEqual(parts(next).month, 2)
        XCTAssertEqual(parts(next).day, 28, "the 31st in February is its last day")

        let yearly = Item.nextMonthly(day: 12, month: 3, hour: 9, minute: 0, after: now, calendar: utc)
        XCTAssertEqual(parts(yearly).year, 2027)
        XCTAssertEqual(parts(yearly).month, 3)

        let due = utc.date(from: DateComponents(year: 2026, month: 11, day: 10))!
        var cursor = now
        var nudges: [Int] = []
        while let nudge = Item.nextDeadlineNudge(due: due, hour: 10, minute: 0, after: cursor, calendar: utc) {
            nudges.append(parts(nudge).day ?? 0)
            cursor = nudge
        }
        XCTAssertEqual(nudges, [3, 7, 9, 10], "7, 3 and 1 day before, and on the day")
        XCTAssertEqual(Item.deadlineLine(due: due, now: now, calendar: utc).prefix(14), "Due in 20 days")
        XCTAssertEqual(Item.ordinal(1), "1st")
        XCTAssertEqual(Item.ordinal(12), "12th")
        XCTAssertEqual(Item.ordinal(22), "22nd")
    }
}
