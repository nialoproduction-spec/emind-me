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

    var kind: ItemKind {
        get { ItemKind(rawValue: kindRaw) ?? .goal }
        set { kindRaw = newValue.rawValue }
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
        nextFireDate: Date? = nil
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
    }

    convenience init(from parsed: ParsedItem) {
        self.init(
            title: parsed.title,
            kind: parsed.kind,
            intervalSeconds: parsed.intervalSeconds,
            hour: parsed.hour,
            minute: parsed.minute,
            weekdaysRaw: parsed.weekdays.isEmpty ? nil : Array(parsed.weekdays).sorted(),
            targetDate: parsed.targetDate
        )
        self.nextFireDate = computeNextFireDate()
    }

    // MARK: - Scheduling

    /// Recomputes when this item is next due, from `reference` forward.
    /// Call this after every fire (advances past the one just handled) and
    /// again on wake (in case the Mac was asleep through the stored value).
    /// Routines only — always nil for goals.
    func computeNextFireDate(after reference: Date = .now, calendar: Calendar = .current) -> Date? {
        switch kind {
        case .goal:
            return nil

        case .repeatingRoutine:
            guard let interval = intervalSeconds, interval > 0 else { return nil }
            return reference.addingTimeInterval(interval)

        case .scheduledRoutine:
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
