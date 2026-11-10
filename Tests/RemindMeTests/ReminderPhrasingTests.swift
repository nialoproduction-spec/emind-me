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
        at("call mom on monday at 9am", 9, days: [2]),
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
