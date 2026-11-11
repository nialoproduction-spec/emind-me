import XCTest
@testable import RemindMe

/// Everyday ways people write a reminder. Each phrase must land in the right
/// kind with the right time, so the app understands what people actually type.
/// All mismatches are collected and reported together.
final class ReminderPhrasingTests: XCTestCase {

    private struct Expect {
        let text: String
        var kind: ItemKind
        var hour: Int? = nil
        var minute: Int? = nil
        var interval: Double? = nil
        var weekdays: Set<Int>? = nil
        var monthDay: Int? = nil
        var yearMonth: Int? = nil
        var oneTime = false
        var timer = false
        var title: String? = nil
        /// Any other check: returns a problem, or nil when it's right.
        var check: ((ParsedItem) -> String?)? = nil
    }

    private static func rule(_ text: String, _ kind: ItemKind = .scheduledRoutine,
                             _ check: @escaping (ParsedItem) -> String?) -> Expect {
        Expect(text: text, kind: kind, check: check)
    }

    /// "9:00 AM, 9:00 PM": first time and the extra ones, in minutes.
    private static func times(_ text: String, _ first: Int, _ extra: [Int], title: String? = nil) -> Expect {
        Expect(text: text, kind: .scheduledRoutine, hour: first / 60, minute: first % 60, title: title) { p in
            (p.extras.extraTimes ?? []) == extra ? nil : "extra times \(p.extras.extraTimes ?? []) want \(extra)"
        }
    }

    private static func window(_ text: String, every seconds: Double, _ start: Int, _ end: Int,
                               days: Set<Int>? = nil) -> Expect {
        Expect(text: text, kind: .repeatingRoutine, interval: seconds, weekdays: days) { p in
            (p.extras.windowStart == start && p.extras.windowEnd == end) ? nil
                : "window \(String(describing: p.extras.windowStart))–\(String(describing: p.extras.windowEnd)) want \(start)–\(end)"
        }
    }

    private static func monthWeek(_ text: String, _ nth: Int, _ day: Int, hour: Int = 9) -> Expect {
        Expect(text: text, kind: .scheduledRoutine, hour: hour, weekdays: [day]) { p in
            p.extras.monthWeek == nth ? nil : "monthWeek \(String(describing: p.extras.monthWeek)) want \(nth)"
        }
    }

    private static func step(_ text: String, days: Int? = nil, weeks: Int? = nil, hour: Int,
                             weekdays: Set<Int>? = nil) -> Expect {
        Expect(text: text, kind: .scheduledRoutine, hour: hour, weekdays: weekdays) { p in
            if p.extras.dayStep != days { return "dayStep \(String(describing: p.extras.dayStep)) want \(String(describing: days))" }
            if p.extras.weekStep != weeks { return "weekStep \(String(describing: p.extras.weekStep)) want \(String(describing: weeks))" }
            return nil
        }
    }

    private static func ends(_ text: String, _ kind: ItemKind = .scheduledRoutine, hour: Int? = nil,
                             interval: Double? = nil) -> Expect {
        Expect(text: text, kind: kind, hour: hour, interval: interval) { p in
            p.extras.endsOn == nil ? "no end date" : nil
        }
    }

    private static func every(_ text: String, _ seconds: Double, title: String? = nil) -> Expect {
        Expect(text: text, kind: .repeatingRoutine, interval: seconds, title: title)
    }

    private static func at(_ text: String, _ hour: Int, _ minute: Int = 0, days: Set<Int>? = nil,
                           title: String? = nil, oneTime: Bool = false) -> Expect {
        Expect(text: text, kind: .scheduledRoutine, hour: hour, minute: minute,
               weekdays: days, oneTime: oneTime, title: title)
    }

    private static func goal(_ text: String) -> Expect {
        Expect(text: text, kind: .goal)
    }

    private static let cases: [Expect] = [
        // Every N minutes or hours
        every("drink water every 40 min", 40 * 60, title: "drink water"),
        every("drink water every 40 minutes", 40 * 60),
        every("drink water every 40 mins", 40 * 60),
        every("drink water every 40 minute", 40 * 60),
        every("drink water every 40min", 40 * 60),
        every("drink water every 40m", 40 * 60),
        every("drink water every 40 min.", 40 * 60),
        every("drink water each 40 minutes", 40 * 60),
        every("drink water every hour", 60 * 60),
        every("drink water every 1 hour", 60 * 60),
        every("drink water every 2 hours", 2 * 60 * 60),
        every("drink water every 2 hrs", 2 * 60 * 60),
        every("stand up every 15 mins", 15 * 60),
        every("stretch every 3 days", 3 * 24 * 60 * 60),
        every("water every forty minutes", 40 * 60),
        every("drink water evry 40 min", 40 * 60),
        every("DRINK WATER EVERY 40 MINUTES", 40 * 60),
        every("remind me to drink water every 40 minutes", 40 * 60, title: "drink water"),

        // Clock times
        at("call mom at 6pm", 18, title: "call mom"),
        at("call mom at 6 pm", 18),
        at("call mom at 6:30pm", 18, 30),
        at("call mom at 6:30 pm", 18, 30),
        at("call mom at 6.30pm", 18, 30),
        at("call mom at 6.30 PM", 18, 30),
        at("call mom at 18:00", 18),
        at("call mom at 9am", 9),
        at("call mom at 9 a.m.", 9),
        at("call mom at 9:15am", 9, 15),
        at("call mom at noon", 12),
        at("call mom at 6 o'clock", 6),
        at("call mom 6pm", 18),
        at("call mom 6:30pm", 18, 30),
        at("call mom every 6pm", 18),
        at("every day at 6pm call mom", 18, days: [], title: "call mom"),
        at("every day at 6pm", 18, days: []),
        at("daily at 6pm call mom", 18, days: []),
        at("everyday at 6pm call mom", 18, days: []),
        at("each day at 6pm call mom", 18, days: []),
        at("call mom at 6pm every day", 18, days: []),
        at("call mom at 6pm daily", 18, days: []),

        // Weekdays
        at("call mom every monday at 9am", 9, days: [2]),
        at("call mom on monday at 9am", 9, days: [], oneTime: true), // one day named, no "every": once
        at("call mom at 6pm", 18, days: [], oneTime: true),          // no repeat word: once
        at("call mom tuesdays at 9am", 9, days: [3]),
        at("call mom thursdays at 9am", 9, days: [5]),
        at("review notes at 5pm every week", 17),
        at("review notes weekly at 5pm", 17),
        at("call mom mondays at 9am", 9, days: [2]),
        at("call mom every mon at 9am", 9, days: [2]),
        at("call mom every tuesday at 9am", 9, days: [3]),
        at("call mom every tues at 9am", 9, days: [3]),
        at("call mom every wednesday at 9am", 9, days: [4]),
        at("call mom every thursday at 9am", 9, days: [5]),
        at("call mom every thur at 9am", 9, days: [5]),
        at("call mom every friday at 9am", 9, days: [6]),
        at("call mom every saturday at 9am", 9, days: [7]),
        at("call mom every sunday at 9am", 9, days: [1]),
        at("call mom every weekday at 9am", 9, days: [2, 3, 4, 5, 6]),
        at("call mom on weekdays at 9am", 9, days: [2, 3, 4, 5, 6]),
        at("call mom every weekend at 9am", 9, days: [1, 7]),
        at("call mom on weekends at 9am", 9, days: [1, 7]),
        at("call mom every monday and friday at 9am", 9, days: [2, 6]),
        at("call mom every mon wed fri at 9am", 9, days: [2, 4, 6]),

        // One-time: today, tomorrow, in a while, on a date
        at("call mom tomorrow at 3pm", 15, oneTime: true),
        at("call mom tomorrow 3pm", 15, oneTime: true),
        at("call mom tomorrow at 3 pm", 15, oneTime: true),
        at("call mom tonight at 9pm", 21, oneTime: true),
        at("call mom today at 5pm", 17, oneTime: true),
        at("call mom at 5pm today", 17, oneTime: true),
        at("call mom at 5pm tomorrow", 17, oneTime: true),
        Expect(text: "call mom in 2 hours", kind: .scheduledRoutine, oneTime: true),
        Expect(text: "call mom in 20 min", kind: .scheduledRoutine, oneTime: true),
        Expect(text: "call mom in 20 minutes", kind: .scheduledRoutine, oneTime: true),
        Expect(text: "call mom in 1 hr", kind: .scheduledRoutine, oneTime: true),
        Expect(text: "call mom after 30 minutes", kind: .scheduledRoutine, oneTime: true),
        Expect(text: "call mom in half an hour", kind: .scheduledRoutine, oneTime: true),
        at("call mom on nov 5 at 10am", 10, oneTime: true),
        at("call mom nov 5 10am", 10, oneTime: true),
        at("call mom on november 5 at 10am", 10, oneTime: true),
        at("call mom on 5 nov at 10am", 10, oneTime: true),
        at("call mom on 5th november at 10am", 10, oneTime: true),
        at("call mom 5 november 10am", 10, oneTime: true),
        at("call mom next monday at 10am", 10, oneTime: true),

        // Monthly and yearly
        Expect(text: "pay rent on the 1st", kind: .scheduledRoutine, monthDay: 1),
        Expect(text: "pay rent every month on the 1st", kind: .scheduledRoutine, monthDay: 1),
        Expect(text: "pay rent monthly on the 15th at 10am", kind: .scheduledRoutine, hour: 10, monthDay: 15),
        Expect(text: "pay rent on the 1st at 9am", kind: .scheduledRoutine, hour: 9, monthDay: 1),
        Expect(text: "anniversary every mar 12", kind: .scheduledRoutine, monthDay: 12, yearMonth: 3),
        Expect(text: "anniversary every march 12", kind: .scheduledRoutine, monthDay: 12, yearMonth: 3),
        Expect(text: "birthday every year on march 12", kind: .scheduledRoutine, monthDay: 12, yearMonth: 3),
        Expect(text: "call mom yearly on dec 25", kind: .scheduledRoutine, monthDay: 25, yearMonth: 12),

        // Timers (a countdown, not a reminder)
        Expect(text: "edit video within 20 min", kind: .goal, timer: true),
        Expect(text: "choosing music within 30 min", kind: .goal, timer: true),
        Expect(text: "edit video 20 min", kind: .goal, timer: true),
        Expect(text: "write song 10 min", kind: .goal, timer: true),
        Expect(text: "drink water within 40 minute", kind: .goal, timer: true),

        // Work and rest
        every("work 25 min and rest 5 min", 25 * 60),
        every("rest every 40 min and take a 10 min break", 40 * 60),

        // Lead-in words people put in front
        at("remind me to call mom at 6pm", 18, title: "call mom"),
        at("reminder to call mom at 6pm", 18, title: "call mom"),
        at("don't forget to call mom at 6pm", 18, title: "call mom"),
        at("dont forget to call mom at 6pm", 18, title: "call mom"),
        at("remember to call mom at 6pm", 18, title: "call mom"),
        at("set alarm to call mom at 6pm", 18, title: "call mom"),
        at("alert me to call mom at 6pm", 18, title: "call mom"),
        at("wake me up at 7am", 7),
        at("wake up at 7am", 7),
        at("call mom at 6pm please", 18, title: "call mom"),

        // ---- Batch 2 ----

        // Part of the day and clock words
        at("take pills every morning", 8, days: [], title: "take pills"),
        at("take pills every afternoon", 14),
        at("take pills every evening", 19),
        at("take pills every night", 21),
        at("take pills at night", 21, title: "take pills"),
        at("walk mornings", 8),
        at("walk every night at 10pm", 22),
        at("call mom at 6 in the evening", 18),
        at("wake up at 7 in the morning", 7),
        at("call mom at 10 at night", 22),
        at("call mom at half past 6pm", 18, 30),
        at("call mom at quarter past 9am", 9, 15),
        at("call mom at quarter to 7pm", 18, 45),
        at("lunch at midday", 12),
        at("call mom at 12am", 0),
        at("call mom at 12pm", 12),
        at("call mom at midnight", 0),
        Expect(text: "call mom @ 6pm", kind: .scheduledRoutine, hour: 18) { p in
            p.title.contains("@") ? "title '\(p.title)' keeps @" : nil
        },

        // More intervals
        every("drink water hourly", 60 * 60),
        every("drink water every half hour", 30 * 60),
        every("drink water every half an hour", 30 * 60),
        every("drink water every quarter hour", 15 * 60),
        every("drink water every 90 minutes", 90 * 60),
        every("drink water every 1.5 hours", 90 * 60),
        every("water plants every other day", 2 * 86_400),

        // Active hours, some days only
        window("drink water every 40 min from 9am to 6pm", every: 2400, 540, 1080),
        window("drink water every hour between 9 and 5", every: 3600, 540, 1020),
        window("drink water every hour 9am-6pm", every: 3600, 540, 1080),
        window("drink water every 30 min from 10 to 6pm", every: 1800, 600, 1080),
        window("drink water every hour from 2 to 6pm", every: 3600, 840, 1080),
        window("drink water every hour from 9am to 5pm on weekdays", every: 3600, 540, 1020, days: [2, 3, 4, 5, 6]),
        Expect(text: "stretch every hour on weekdays", kind: .repeatingRoutine, interval: 3600, weekdays: [2, 3, 4, 5, 6]),

        // Several times a day
        times("take pills at 9am and 9pm", 540, [1260], title: "take pills"),
        times("take pills at 8am, 1pm and 8pm", 480, [780, 1200], title: "take pills"),
        times("take pills twice a day", 540, [1260], title: "take pills"),
        times("take pills twice daily", 540, [1260]),
        times("take pills 3 times a day", 480, [840, 1200]),
        times("take pills three times a day", 480, [840, 1200]),
        times("take pills once a day", 540, []),

        // Every N days or weeks at a time
        step("water plants every other day at 7am", days: 2, hour: 7),
        step("water plants every 2 days at 9am", days: 2, hour: 9),
        step("water plants every 3 days at 9am", days: 3, hour: 9),
        step("call mom every 1 day at 6pm", hour: 18),
        step("clean every other friday", weeks: 2, hour: 9, weekdays: [6]),
        step("clean every other friday at 5pm", weeks: 2, hour: 17, weekdays: [6]),
        step("team sync every 2 weeks on monday at 10am", weeks: 2, hour: 10, weekdays: [2]),
        step("payroll biweekly on friday", weeks: 2, hour: 9, weekdays: [6]),
        step("payroll fortnightly on friday at 4pm", weeks: 2, hour: 16, weekdays: [6]),
        step("clean every second monday", weeks: 2, hour: 9, weekdays: [2]),

        // Nth weekday of the month
        monthWeek("team meeting first monday of the month", 1, 2),
        monthWeek("team meeting on the first monday of every month at 10am", 1, 2, hour: 10),
        monthWeek("pay bills last friday of the month", -1, 6),
        monthWeek("book club every third thursday at 7pm", 3, 5, hour: 19),
        monthWeek("review 2nd tuesday of the month", 2, 3),
        Expect(text: "pay bills every month on the first monday", kind: .scheduledRoutine, hour: 9,
               weekdays: [2], title: "pay bills") { p in
            p.extras.monthWeek == 1 ? (p.title.lowercased() == "pay bills" ? nil : "title '\(p.title)'") : "monthWeek \(String(describing: p.extras.monthWeek))"
        },

        // End of the month
        Expect(text: "pay rent on the last day of the month", kind: .scheduledRoutine, monthDay: 31),
        Expect(text: "send invoice at the end of every month", kind: .scheduledRoutine, monthDay: 31),

        // For a while, or until a date
        ends("take pills at 9am for 7 days", hour: 9),
        ends("take pills every 8 hours for 5 days", .repeatingRoutine, interval: 8 * 3600),
        ends("stretch every morning for 2 weeks", hour: 8),
        ends("take pills twice a day for a week", hour: 9),
        ends("take pills at 9am until dec 1", hour: 9),
        ends("take pills at 9am till 5 december", hour: 9),

        // More one-time wording
        Expect(text: "call mom tomorrow morning", kind: .scheduledRoutine, oneTime: true),
        Expect(text: "call mom tomorrow evening", kind: .scheduledRoutine, oneTime: true),
        at("call mom this evening", 19, oneTime: true),
        at("call mom this friday at 5pm", 17, oneTime: true),
        at("call mom tomorrow at night", 21, oneTime: true),
        Expect(text: "call mom in an hour", kind: .scheduledRoutine, oneTime: true),
        Expect(text: "call mom in 3 days", kind: .scheduledRoutine, oneTime: true),
        Expect(text: "call mom in a week", kind: .scheduledRoutine, oneTime: true),
        at("call mom day after tomorrow at 10am", 10, oneTime: true),
        at("call mom tmrw at 3pm", 15, oneTime: true),
        Expect(text: "remind me in 10 minutes to stretch", kind: .scheduledRoutine, oneTime: true, title: "stretch"),
        Expect(text: "remind me to stretch in 10 minutes", kind: .scheduledRoutine, oneTime: true, title: "stretch"),

        // Yearly and deadlines
        Expect(text: "wish rahul happy birthday on march 12 every year", kind: .scheduledRoutine,
               monthDay: 12, yearMonth: 3),
        Expect(text: "anniversary annually on june 5", kind: .scheduledRoutine, monthDay: 5, yearMonth: 6),
        rule("sharma wedding teaser due nov 20") { p in p.dueDate == nil ? "no deadline" : nil },

        // Word order and typos
        at("at 6pm call mom", 18, title: "call mom"),
        at("6pm call mom", 18, title: "call mom"),
        every("drink watr evry 40 mins", 40 * 60),

        // Timers that must stay timers
        Expect(text: "color grade for 30 min", kind: .goal, timer: true),
        Expect(text: "export within 1 hour", kind: .goal, timer: true),

        // Plain tasks with no time are goals
        goal("call mom"),
        goal("buy milk"),
    ]

    func testEveryCommonPhrasingIsUnderstood() {
        var failures: [String] = []
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 9))!

        for c in Self.cases {
            let p = ItemParser.parse(c.text, now: now, calendar: calendar)
            var problems: [String] = []

            if c.timer {
                if p.timer == nil { problems.append("not a timer") }
            } else {
                if p.kind != c.kind { problems.append("kind \(p.kind) want \(c.kind)") }
                if let hour = c.hour, p.hour != hour { problems.append("hour \(String(describing: p.hour)) want \(hour)") }
                if let minute = c.minute, p.minute != minute { problems.append("minute \(String(describing: p.minute)) want \(minute)") }
                if let interval = c.interval, p.intervalSeconds != interval {
                    problems.append("interval \(String(describing: p.intervalSeconds)) want \(interval)")
                }
                if let days = c.weekdays, p.weekdays != days { problems.append("weekdays \(p.weekdays.sorted()) want \(days.sorted())") }
                if let day = c.monthDay, p.monthDay != day { problems.append("monthDay \(String(describing: p.monthDay)) want \(day)") }
                if let month = c.yearMonth, p.yearMonth != month { problems.append("yearMonth \(String(describing: p.yearMonth)) want \(month)") }
                if c.oneTime, p.onceAt == nil { problems.append("no one-time date") }
            }
            if let check = c.check, let problem = check(p) { problems.append(problem) }
            if let title = c.title, !p.title.lowercased().contains(title) {
                problems.append("title '\(p.title)' lacks '\(title)'")
            }
            if !problems.isEmpty {
                failures.append("\"\(c.text)\": " + problems.joined(separator: "; "))
            }
        }
        XCTAssertTrue(failures.isEmpty, "\(failures.count) phrases not understood:\n" + failures.joined(separator: "\n"))
    }
}
