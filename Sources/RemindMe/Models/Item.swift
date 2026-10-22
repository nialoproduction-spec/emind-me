import Foundation
import SwiftData

enum ItemKind: Int, Codable, CaseIterable {
    /// Fires repeatedly at a fixed interval — "drink water every 40 minutes".
    case repeatingRoutine = 0
    /// Fires at a clock time, daily or on chosen weekdays — "walk at 4am every day".
    case scheduledRoutine = 1
    /// No alert, ever. Just tracked, with an optional target date — "go to Godavari".
    case goal = 2
}

/// How a routine behaves when it comes due.
enum ReminderStyle: Int, Codable, CaseIterable {
    /// Tracked: the card stays until Done / Snooze / Skip, nags, counts in the
    /// checklist and streaks. This is how every routine behaved before styles
    /// existed, so a missing value means `.habit`.
    case habit = 0
    /// Just a heads-up: a small popup with a face and the title that goes
    /// away by itself. No buttons, no nagging, no checklist entry.
    case justRemind = 1
}

/// What the person picks in the confirmation bar.
enum ItemType: String, CaseIterable {
    case reminder, habit, goal

    var label: String {
        switch self {
        case .reminder: return "Reminder"
        case .habit: return "Habit"
        case .goal: return "Goal"
        }
    }

    var icon: String {
        switch self {
        case .reminder: return "bell"
        case .habit: return "checkmark.circle"
        case .goal: return "flag"
        }
    }

    /// One plain line on what it does.
    var explanation: String {
        switch self {
        case .reminder: return "Just reminds you. No buttons to press."
        case .habit: return "Stays until you tap Done, Snooze or Skip."
        case .goal: return "Checked at 8 PM each day until it's done."
        }
    }
}

@Model
final class Item {
    var id: UUID
    var title: String
    var kindRaw: Int
    var createdAt: Date

    /// Routines only: whether it's currently running. Paused routines keep
    /// their settings but stop notifying until resumed.
    var isActive: Bool
    /// Goals only: whether it's been marked done.
    var isAchieved: Bool

    // Repeating routine
    var intervalSeconds: Double?

    // Scheduled routine
    var hour: Int?
    var minute: Int?
    /// Calendar weekday ints, 1 (Sunday) through 7 (Saturday). Empty or nil
    /// means every day.
    var weekdaysRaw: [Int]?

    // Goal
    var targetDate: Date?

    /// Absolute timestamp of the next time this item is due. Recomputed
    /// after every fire (`computeNextFireDate`) and re-checked on wake —
    /// never derived from a running countdown, so sleep can't make it drift.
    /// Always nil for goals.
    var nextFireDate: Date?

    /// On a timed pause until this moment, then resumes by itself. Nil when
    /// running, or when paused with no end ("until I resume").
    var pausedUntil: Date?
    /// Optional category, e.g. "Health" or "Work".
    var category: String?
    /// When its schedule was last edited. Smart suggestions only learn from
    /// reminders after this, so an applied suggestion isn't suggested again.
    var scheduleEditedAt: Date?
    /// Routines only. Nil on anything saved before styles existed (= habit).
    var styleRaw: Int?

    // One-time, monthly, yearly, deadlines (all optional: older stores open
    // with them empty, and those items keep their daily / weekly schedule).

    /// One-time: fires at this moment, once, then it's over ("tomorrow 3pm").
    var onceAt: Date?
    /// Monthly on this day (1–31; short months use their last day), or with
    /// `yearMonth`, yearly ("pay rent on the 1st", "every Mar 12").
    var monthDay: Int?
    /// Yearly: the month (1–12), with `monthDay`.
    var yearMonth: Int?
    /// Deadline: nudges 7, 3 and 1 day before and on the day, at `hour`:`minute`
    /// ("Sharma teaser due Nov 10").
    var dueDate: Date?
    /// Set when it's over: a one-time reminder has fired, a deadline is past
    /// or delivered. It drops out of the lists (history and backups keep it).
    var endedAt: Date?

    var kind: ItemKind {
        get { ItemKind(rawValue: kindRaw) ?? .goal }
        set { kindRaw = newValue.rawValue }
    }

    var style: ReminderStyle {
        get { styleRaw.flatMap(ReminderStyle.init(rawValue:)) ?? .habit }
        set { styleRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        title: String,
        kind: ItemKind,
        createdAt: Date = .now,
        isActive: Bool = true,
        isAchieved: Bool = false,
        intervalSeconds: Double? = nil,
        hour: Int? = nil,
        minute: Int? = nil,
        weekdaysRaw: [Int]? = nil,
        targetDate: Date? = nil,
        nextFireDate: Date? = nil,
        category: String? = nil,
        style: ReminderStyle? = nil
    ) {
        self.id = id
        self.title = title
        self.kindRaw = kind.rawValue
        self.createdAt = createdAt
        self.isActive = isActive
        self.isAchieved = isAchieved
        self.intervalSeconds = intervalSeconds
        self.hour = hour
        self.minute = minute
        self.weekdaysRaw = weekdaysRaw
        self.targetDate = targetDate
        self.nextFireDate = nextFireDate
        self.pausedUntil = nil
        self.category = category
        self.scheduleEditedAt = nil
        self.styleRaw = style?.rawValue
    }

    convenience init(from parsed: ParsedItem, now: Date = .now) {
        let isGoal = parsed.type == .goal
        // A deadline nudges with the little popup; it has nothing to tick off.
        let style: ReminderStyle? = isGoal ? nil
            : (parsed.dueDate != nil ? .justRemind : (parsed.type == .habit ? .habit : .justRemind))
        self.init(
            title: parsed.title,
            kind: isGoal ? .goal : parsed.kind,
            intervalSeconds: isGoal ? nil : parsed.intervalSeconds,
            hour: isGoal ? nil : parsed.hour,
            minute: isGoal ? nil : parsed.minute,
            weekdaysRaw: isGoal || parsed.weekdays.isEmpty ? nil : Array(parsed.weekdays).sorted(),
            targetDate: isGoal ? (parsed.targetDate ?? parsed.dueDate ?? parsed.onceAt) : nil,
            category: parsed.category,
            style: style
        )
        if !isGoal {
            onceAt = parsed.onceAt
            monthDay = parsed.monthDay
            yearMonth = parsed.yearMonth
            dueDate = parsed.dueDate
        }
        nextFireDate = computeNextFireDate(after: now)
        // A one-time reminder for a moment that's just gone: it fires right away.
        if !isGoal, nextFireDate == nil, onceAt != nil { nextFireDate = now }
    }

    // MARK: - Scheduling

    /// What kind of clock-time schedule it is.
    enum Repeat: Equatable {
        case daily, weekly, once, monthly, yearly, deadline
    }

    var repeatKind: Repeat {
        if dueDate != nil { return .deadline }
        if onceAt != nil { return .once }
        if monthDay != nil { return yearMonth != nil ? .yearly : .monthly }
        return (weekdaysRaw?.isEmpty == false) ? .weekly : .daily
    }

    /// Over (fired once, past its deadline, delivered): not in the lists.
    var isOver: Bool { endedAt != nil }

    /// Recomputes when this item is next due, from `reference` forward.
    /// Call this after every fire (advances past the one just handled) and
    /// again on wake (in case the Mac was asleep through the stored value).
    /// Routines only — always nil for goals.
    func computeNextFireDate(after reference: Date = .now, calendar: Calendar = .current) -> Date? {
        guard endedAt == nil else { return nil }
        switch kind {
        case .goal:
            return nil

        case .repeatingRoutine:
            guard let interval = intervalSeconds, interval > 0 else { return nil }
            return reference.addingTimeInterval(interval)

        case .scheduledRoutine:
            if let dueDate {
                return Self.nextDeadlineNudge(due: dueDate, hour: hour ?? 10, minute: minute ?? 0,
                                              after: reference, calendar: calendar)
            }
            if let onceAt { return onceAt > reference ? onceAt : nil }
            if let monthDay {
                return Self.nextMonthly(day: monthDay, month: yearMonth, hour: hour ?? 9, minute: minute ?? 0,
                                        after: reference, calendar: calendar)
            }
            guard let hour, let minute else { return nil }
            let allowedWeekdays: Set<Int> = (weekdaysRaw?.isEmpty == false) ? Set(weekdaysRaw!) : Set(1...7)
            // Scan forward up to a week to find the next day that matches
            // both the weekday filter and is still ahead of `reference`.
            for offset in 0..<8 {
                guard let candidateDay = calendar.date(byAdding: .day, value: offset, to: reference) else { continue }
                guard allowedWeekdays.contains(calendar.component(.weekday, from: candidateDay)) else { continue }
                var comps = calendar.dateComponents([.year, .month, .day], from: candidateDay)
                comps.hour = hour
                comps.minute = minute
                comps.second = 0
                guard let candidate = calendar.date(from: comps), candidate > reference else { continue }
                return candidate
            }
            return nil
        }
    }

    /// The next monthly (or, with `month`, yearly) time after `reference`.
    /// A day past the month's end lands on its last day (the 31st in
    /// February is the 28th or 29th).
    static func nextMonthly(day: Int, month: Int?, hour: Int, minute: Int, after reference: Date,
                            calendar: Calendar = .current) -> Date? {
        let start = calendar.dateComponents([.year, .month], from: reference)
        guard let year = start.year, let thisMonth = start.month else { return nil }
        let steps = month == nil ? 14 : 10 // months, or years
        for offset in 0..<steps {
            var comps = DateComponents()
            if let month {
                comps.year = year + offset
                comps.month = month
            } else {
                let index = (thisMonth - 1) + offset
                comps.year = year + index / 12
                comps.month = index % 12 + 1
            }
            comps.day = 1
            guard let first = calendar.date(from: comps),
                  let days = calendar.range(of: .day, in: .month, for: first)?.count else { continue }
            comps.day = min(max(day, 1), days)
            comps.hour = hour
            comps.minute = minute
            comps.second = 0
            guard let candidate = calendar.date(from: comps), candidate > reference else { continue }
            return candidate
        }
        return nil
    }

    /// Days before a deadline that get a nudge (and the day itself).
    static let deadlineNudgeDays = [7, 3, 1, 0]

    /// The next deadline nudge after `reference`: 7, 3 and 1 day before the
    /// due day, and on it, at the given time. Nil once they've all gone.
    static func nextDeadlineNudge(due: Date, hour: Int, minute: Int, after reference: Date,
                                  calendar: Calendar = .current) -> Date? {
        let dueDay = calendar.startOfDay(for: due)
        for days in deadlineNudgeDays {
            guard let day = calendar.date(byAdding: .day, value: -days, to: dueDay),
                  let nudge = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  nudge > reference else { continue }
            return nudge
        }
        return nil
    }

    /// "Due in 3 days · Tue, Nov 10", "Due tomorrow", "Due today", "Overdue".
    static func deadlineLine(due: Date, now: Date, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: due)).day ?? 0
        let when = deadlineDayFormatter.string(from: due)
        switch days {
        case ..<0: return "Overdue · was due \(when)"
        case 0: return "Due today"
        case 1: return "Due tomorrow · \(when)"
        default: return "Due in \(days) days · \(when)"
        }
    }

    private static let deadlineDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter
    }()

    static func ordinal(_ day: Int) -> String {
        let tens = (day / 10) % 10
        let suffix: String
        switch day % 10 {
        case 1 where tens != 1: suffix = "st"
        case 2 where tens != 1: suffix = "nd"
        case 3 where tens != 1: suffix = "rd"
        default: suffix = "th"
        }
        return "\(day)\(suffix)"
    }

    static let monthNames = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    private static let onceFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// "Once · Tomorrow at 3:00 PM", "10:00 AM · Monthly on the 1st",
    /// "9:00 AM · Every Mar 12", "Due Nov 10 · in 12 days". Nil for daily /
    /// weekly (the usual summary).
    static func specialSummary(repeat kind: Repeat, onceAt: Date?, monthDay: Int?, yearMonth: Int?,
                               dueDate: Date?, hour: Int?, minute: Int?, now: Date = .now) -> String? {
        let time = clockTimeString(hour: hour ?? 9, minute: minute ?? 0)
        switch kind {
        case .once:
            guard let onceAt else { return nil }
            return "Once · \(onceFormatter.string(from: onceAt))"
        case .monthly:
            guard let monthDay else { return nil }
            return "\(time) · Monthly on the \(ordinal(monthDay))"
        case .yearly:
            guard let monthDay, let yearMonth, (1...12).contains(yearMonth) else { return nil }
            return "\(time) · Every \(monthNames[yearMonth]) \(monthDay)"
        case .deadline:
            guard let dueDate else { return nil }
            return deadlineLine(due: dueDate, now: now)
        case .daily, .weekly:
            return nil
        }
    }

    // MARK: - Display helpers

    private static let weekdaySymbols = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("j:mm")
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// One line describing the schedule, for list rows and the collapsed pill.
    var scheduleSummary: String {
        switch kind {
        case .repeatingRoutine:
            guard let interval = intervalSeconds else { return "" }
            return "every \(Self.durationString(interval))"
        case .scheduledRoutine:
            if let special = Self.specialSummary(repeat: repeatKind, onceAt: onceAt, monthDay: monthDay,
                                                 yearMonth: yearMonth, dueDate: dueDate,
                                                 hour: hour, minute: minute) {
                return special
            }
            guard let hour, let minute else { return "" }
            let time = Self.clockTimeString(hour: hour, minute: minute)
            let days = weekdaysRaw ?? []
            if days.isEmpty || days.count == 7 {
                return "\(time) · Daily"
            }
            let names = days.sorted().map { Self.weekdaySymbols[$0] }.joined(separator: ", ")
            return "\(time) · \(names)"
        case .goal:
            guard let targetDate else { return "" }
            return "by \(Self.dateFormatter.string(from: targetDate))"
        }
    }

    static func clockTimeString(hour: Int, minute: Int) -> String {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let date = Calendar.current.date(from: comps) ?? .now
        return clockFormatter.string(from: date)
    }

    static func durationString(_ seconds: Double) -> String {
        if seconds >= 604800, seconds.truncatingRemainder(dividingBy: 604800) == 0 {
            let weeks = Int(seconds / 604800)
            return weeks == 1 ? "1 week" : "\(weeks) weeks"
        }
        if seconds >= 86400, seconds.truncatingRemainder(dividingBy: 86400) == 0 {
            let days = Int(seconds / 86400)
            return days == 1 ? "1 day" : "\(days) days"
        }
        if seconds >= 3600, seconds.truncatingRemainder(dividingBy: 3600) == 0 {
            let hours = Int(seconds / 3600)
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
        if seconds >= 60 {
            let minutes = Int((seconds / 60).rounded())
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        }
        let secs = Int(seconds)
        return secs == 1 ? "1 second" : "\(secs) seconds"
    }
}
