import Foundation

/// Schedule rules beyond one time a day: active hours for "every 40 min",
/// several times a day, every N days or weeks, the Nth weekday of the month,
/// and an end date. Stored on `Item` as one JSON field (`extrasData`), so a
/// new rule never needs a SwiftData migration. All empty = none.
struct ScheduleExtras: Codable, Equatable {
    /// Active hours for interval reminders, in minutes after midnight
    /// ("every 40 min from 9am to 6pm" = 540…1080). Can wrap past midnight.
    var windowStart: Int?
    var windowEnd: Int?
    /// More clock times besides the item's own hour:minute ("at 9am and 9pm").
    var extraTimes: [Int]?
    /// Every N days at the clock time ("every other day at 7am" = 2).
    var dayStep: Int?
    /// Every N weeks on the item's weekdays ("every other friday" = 2).
    var weekStep: Int?
    /// The day N-day and N-week steps count from.
    var anchor: Date?
    /// The Nth weekday of the month: 1…5, or -1 for the last ("first monday").
    var monthWeek: Int?
    /// Stops after this moment ("for 7 days", "until Dec 1").
    var endsOn: Date?

    var isEmpty: Bool { self == ScheduleExtras() }
    var hasWindow: Bool { windowStart != nil && windowEnd != nil }
    /// Needs the day-by-day scan rather than the plain daily/weekly one.
    var needsDayScan: Bool {
        (extraTimes?.isEmpty == false) || (dayStep ?? 1) > 1 || (weekStep ?? 1) > 1 || monthWeek != nil
    }
}

/// The date maths for `ScheduleExtras`. Pure, so it's tested directly.
enum ScheduleMath {
    /// Is this minute of the day inside the active hours? A window like
    /// 22:00–02:00 wraps past midnight.
    static func inside(_ minute: Int, start: Int, end: Int) -> Bool {
        start <= end ? (minute >= start && minute <= end) : (minute >= start || minute <= end)
    }

    /// Moves an interval reminder's next time into its active hours and onto
    /// an allowed weekday: a time outside goes to the next window opening.
    static func fit(_ candidate: Date, start: Int?, end: Int?, weekdays: Set<Int>,
                    calendar: Calendar) -> Date? {
        let allowed = weekdays.isEmpty ? Set(1...7) : weekdays
        func ok(_ date: Date) -> Bool {
            guard allowed.contains(calendar.component(.weekday, from: date)) else { return false }
            guard let start, let end else { return true }
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return inside((parts.hour ?? 0) * 60 + (parts.minute ?? 0), start: start, end: end)
        }
        if ok(candidate) { return candidate }
        // A new day starts at the window's opening, or 9 AM when only days are set.
        let opening = start ?? 540
        let firstDay = calendar.startOfDay(for: candidate)
        for offset in 0..<9 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay),
                  let open = calendar.date(bySettingHour: opening / 60, minute: opening % 60, second: 0, of: day),
                  open > candidate, ok(open) else { continue }
            return open
        }
        return nil
    }

    /// The next clock time for schedules with several times a day, every N
    /// days or weeks, or the Nth weekday of the month.
    static func nextClock(times: [Int], weekdays: Set<Int>, extras: ScheduleExtras,
                          after reference: Date, calendar: Calendar) -> Date? {
        let sorted = Array(Set(times)).sorted()
        guard !sorted.isEmpty else { return nil }
        let anchorDay = calendar.startOfDay(for: extras.anchor ?? reference)
        let firstDay = calendar.startOfDay(for: reference)
        for offset in 0..<800 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay),
                  dayAllowed(day, weekdays: weekdays, extras: extras, anchorDay: anchorDay, calendar: calendar)
            else { continue }
            for minutes in sorted {
                guard let candidate = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60,
                                                    second: 0, of: day),
                      candidate > reference else { continue }
                return candidate
            }
        }
        return nil
    }

    static func dayAllowed(_ day: Date, weekdays: Set<Int>, extras: ScheduleExtras, anchorDay: Date,
                           calendar: Calendar) -> Bool {
        if !weekdays.isEmpty, !weekdays.contains(calendar.component(.weekday, from: day)) { return false }
        if let step = extras.dayStep, step > 1 {
            let days = calendar.dateComponents([.day], from: anchorDay, to: day).day ?? 0
            if days < 0 || days % step != 0 { return false }
        }
        if let step = extras.weekStep, step > 1 {
            let anchorWeek = calendar.dateInterval(of: .weekOfYear, for: anchorDay)?.start ?? anchorDay
            let thisWeek = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day
            let days = calendar.dateComponents([.day], from: anchorWeek, to: thisWeek).day ?? 0
            let weeks = Int((Double(days) / 7).rounded())
            if weeks < 0 || weeks % step != 0 { return false }
        }
        if let nth = extras.monthWeek {
            let dayOfMonth = calendar.component(.day, from: day)
            if nth > 0 {
                if (dayOfMonth - 1) / 7 + 1 != nth { return false }
            } else {
                let length = calendar.range(of: .day, in: .month, for: day)?.count ?? 31
                if dayOfMonth + 7 <= length { return false } // not in the month's last 7 days
            }
        }
        return true
    }
}

// MARK: - Describing it

extension ScheduleExtras {
    private static let dayShort = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private static let untilFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    /// "Weekdays", "Weekends", "Daily", or "Mon, Wed, Fri".
    static func dayList(_ days: [Int]) -> String {
        let set = Set(days)
        if set.isEmpty || set.count == 7 { return "Daily" }
        if set == [2, 3, 4, 5, 6] { return "Weekdays" }
        if set == [1, 7] { return "Weekends" }
        return set.sorted().map { dayShort[$0] }.joined(separator: ", ")
    }

    static func ordinalWord(_ n: Int) -> String {
        [-1: "Last", 1: "First", 2: "Second", 3: "Third", 4: "Fourth", 5: "Fifth"][n] ?? ""
    }

    /// "every 40 minutes · 9:00 AM–6:00 PM · Weekdays · until Dec 1"
    static func intervalLine(interval: Double, weekdays: [Int], extras: ScheduleExtras) -> String {
        var parts = ["every \(Item.durationString(interval))"]
        if let start = extras.windowStart, let end = extras.windowEnd {
            parts.append(Item.clockTimeString(hour: start / 60, minute: start % 60) + "–"
                         + Item.clockTimeString(hour: end / 60, minute: end % 60))
        }
        if !weekdays.isEmpty, Set(weekdays).count < 7 { parts.append(dayList(weekdays)) }
        if let ends = extras.endsOn { parts.append("until " + untilFormatter.string(from: ends)) }
        return parts.joined(separator: " · ")
    }

    /// "9:00 AM, 9:00 PM · Daily", "7:00 AM · Every 2 days",
    /// "9:00 AM · First Mon of the month", "5:00 PM · Fri, every 2 weeks".
    static func clockLine(hour: Int, minute: Int, weekdays: [Int], extras: ScheduleExtras) -> String {
        let times = Array(Set([hour * 60 + minute] + (extras.extraTimes ?? []))).sorted()
        var parts = [times.map { Item.clockTimeString(hour: $0 / 60, minute: $0 % 60) }.joined(separator: ", ")]
        if let nth = extras.monthWeek {
            let names = weekdays.isEmpty ? "day" : Set(weekdays).sorted().map { dayShort[$0] }.joined(separator: ", ")
            parts.append("\(ordinalWord(nth)) \(names) of the month")
        } else if let step = extras.weekStep, step > 1 {
            parts.append("\(dayList(weekdays)), every \(step) weeks")
        } else if let step = extras.dayStep, step > 1 {
            parts.append("Every \(step) days")
        } else {
            parts.append(dayList(weekdays))
        }
        if let ends = extras.endsOn { parts.append("until " + untilFormatter.string(from: ends)) }
        return parts.joined(separator: " · ")
    }
}
