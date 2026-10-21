import Foundation
import SwiftData

/// History, streaks, the weekly summary and smart suggestions — all worked
/// out from the stored occurrences, on the Mac, nothing sent anywhere.
/// Pure functions of their inputs (plus a calendar), so they're easy to test.
enum Insights {

    // MARK: - Days

    struct DayRecord: Equatable {
        let day: Date
        var done = 0
        var skipped = 0
        var unfinished = 0
        var pending = 0

        var total: Int { done + skipped + unfinished + pending }
        var isEmpty: Bool { total == 0 }
        /// A day counts toward a streak when at least half of that day's
        /// reminders were done.
        var isKept: Bool { total > 0 && done * 2 >= total }
    }

    /// Occurrences that belong to `item`, matched by identifier.
    static func occurrences(of item: Item, in all: [Occurrence]) -> [Occurrence] {
        let id = item.persistentModelID
        return all.filter { $0.item?.persistentModelID == id }
    }

    /// One record per day for the last `days` days, oldest first, ending today.
    static func dailyRecords(_ occurrences: [Occurrence], days: Int, now: Date,
                             calendar: Calendar = .current) -> [DayRecord] {
        let today = calendar.startOfDay(for: now)
        let starts = (0..<max(days, 1)).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        var byDay = Dictionary(uniqueKeysWithValues: starts.map { ($0, DayRecord(day: $0)) })
        for occurrence in occurrences {
            let day = calendar.startOfDay(for: occurrence.scheduledFireDate)
            guard byDay[day] != nil else { continue }
            switch occurrence.status {
            case .done: byDay[day]!.done += 1
            case .skipped: byDay[day]!.skipped += 1
            case .unfinished: byDay[day]!.unfinished += 1
            case .pending: byDay[day]!.pending += 1
            }
        }
        return starts.reversed().compactMap { byDay[$0] }
    }

    /// A month laid out as weeks for the habit calendar: `nil` pads the days
    /// before the 1st (from the calendar's first weekday) and after the last.
    static func monthGrid(_ occurrences: [Occurrence], month: Date, calendar: Calendar = .current) -> [[DayRecord?]] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let days = calendar.range(of: .day, in: .month, for: interval.start)?.count else { return [] }
        var byDay: [Date: DayRecord] = [:]
        for offset in 0..<days {
            if let day = calendar.date(byAdding: .day, value: offset, to: interval.start) {
                byDay[day] = DayRecord(day: day)
            }
        }
        for occurrence in occurrences {
            let day = calendar.startOfDay(for: occurrence.scheduledFireDate)
            guard byDay[day] != nil else { continue }
            switch occurrence.status {
            case .done: byDay[day]!.done += 1
            case .skipped: byDay[day]!.skipped += 1
            case .unfinished: byDay[day]!.unfinished += 1
            case .pending: byDay[day]!.pending += 1
            }
        }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let lead = (firstWeekday - calendar.firstWeekday + 7) % 7
        var cells: [DayRecord?] = Array(repeating: nil, count: lead)
        for offset in 0..<days {
            if let day = calendar.date(byAdding: .day, value: offset, to: interval.start) { cells.append(byDay[day]) }
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    /// Kept days in a row, counting back from today. Days with no reminders
    /// (paused, or not one of its weekdays) don't break it, and today never
    /// breaks it while it's still in progress.
    static func streak(_ records: [DayRecord]) -> Int {
        var count = 0
        for (index, record) in records.reversed().enumerated() {
            if record.isKept { count += 1; continue }
            if record.isEmpty { continue }
            if index == 0 { continue } // today, not over yet
            break
        }
        return count
    }

    /// Done ÷ answered-or-missed (pending ones aren't counted yet).
    static func completionRate(_ records: [DayRecord]) -> Double? {
        let decided = records.reduce(0) { $0 + $1.done + $1.skipped + $1.unfinished }
        guard decided > 0 else { return nil }
        return Double(records.reduce(0) { $0 + $1.done }) / Double(decided)
    }

    // MARK: - Weekly summary

    struct RoutineWeek: Identifiable, Equatable {
        let id: PersistentIdentifier
        let title: String
        let category: String?
        let done: Int
        let total: Int
        let streak: Int
        let snoozed: Int
    }

    struct WeeklySummary: Equatable {
        let start: Date
        let end: Date
        let done: Int
        let skipped: Int
        let unfinished: Int
        let total: Int
        let routines: [RoutineWeek]
        let openGoals: Int

        var rate: Double? {
            let decided = done + skipped + unfinished
            return decided > 0 ? Double(done) / Double(decided) : nil
        }
        var bestStreak: RoutineWeek? {
            routines.filter { $0.streak > 0 }.max { $0.streak < $1.streak }
        }
        var mostSnoozed: RoutineWeek? {
            routines.filter { $0.snoozed > 0 }.max { $0.snoozed < $1.snoozed }
        }
    }

    /// The last 7 days, today included.
    static func weeklySummary(items: [Item], occurrences: [Occurrence], now: Date,
                              calendar: Calendar = .current) -> WeeklySummary {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let inWeek = occurrences.filter { $0.scheduledFireDate >= start && $0.scheduledFireDate <= now }

        var routines: [RoutineWeek] = []
        for item in items where item.kind != .goal {
            let mine = Self.occurrences(of: item, in: occurrences)
            let week = mine.filter { $0.scheduledFireDate >= start && $0.scheduledFireDate <= now }
            guard !week.isEmpty else { continue }
            routines.append(RoutineWeek(
                id: item.persistentModelID,
                title: item.title,
                category: item.category,
                done: week.filter { $0.status == .done }.count,
                total: week.count,
                streak: streak(dailyRecords(mine, days: 60, now: now, calendar: calendar)),
                snoozed: week.filter { ($0.snoozedMinutes ?? 0) > 0 }.count
            ))
        }
        routines.sort { $0.total == $1.total ? $0.title < $1.title : $0.total > $1.total }

        return WeeklySummary(
            start: start,
            end: now,
            done: inWeek.filter { $0.status == .done }.count,
            skipped: inWeek.filter { $0.status == .skipped }.count,
            unfinished: inWeek.filter { $0.status == .unfinished }.count,
            total: inWeek.count,
            routines: routines,
            openGoals: items.filter { $0.kind == .goal && !$0.isAchieved }.count
        )
    }

    /// Identifies a week ("2026-W42") so the weekly summary shows once per week.
    static func weekKey(for date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", comps.yearForWeekOfYear ?? 0, comps.weekOfYear ?? 0)
    }

    // MARK: - Smart suggestions

    struct Suggestion: Identifiable, Equatable {
        enum Action: Equatable {
            case moveTime(hour: Int, minute: Int)
            case setInterval(seconds: Double)
        }
        let id: String
        let itemID: PersistentIdentifier
        let message: String
        let actionLabel: String
        let action: Action
    }

    /// How many recent reminders a suggestion looks at, and how many of them
    /// must agree before it speaks up.
    static let lookBack = 5
    static let needed = 3

    static func suggestions(items: [Item], occurrences: [Occurrence],
                            calendar: Calendar = .current) -> [Suggestion] {
        var result: [Suggestion] = []
        for item in items where item.kind != .goal && item.isActive {
            // Only what happened since its schedule was last changed.
            let since = item.scheduleEditedAt ?? .distantPast
            let recent = Self.occurrences(of: item, in: occurrences)
                .filter { $0.scheduledFireDate > since }
                .sorted { $0.scheduledFireDate > $1.scheduledFireDate }
                .prefix(lookBack)
            if let suggestion = timeSuggestion(item, recent: Array(recent), calendar: calendar)
                ?? snoozeSuggestion(item, recent: Array(recent)) {
                result.append(suggestion)
            }
        }
        return result
    }

    /// "You usually do it around 4:35 — move it there?" for timed routines
    /// done consistently 20+ minutes off their set time.
    private static func timeSuggestion(_ item: Item, recent: [Occurrence], calendar: Calendar) -> Suggestion? {
        guard item.kind == .scheduledRoutine, let hour = item.hour, let minute = item.minute else { return nil }
        // Measured against the time it's set to now, by time of day.
        let setAt = Double(hour * 60 + minute)
        let offsets = recent.compactMap { occurrence -> Double? in
            guard occurrence.status == .done, let resolved = occurrence.resolvedAt else { return nil }
            let parts = calendar.dateComponents([.hour, .minute], from: resolved)
            var minutes = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) - setAt
            if minutes > 720 { minutes -= 1440 }
            if minutes < -720 { minutes += 1440 }
            return abs(minutes) <= 180 ? minutes : nil
        }
        guard offsets.count >= needed else { return nil }
        let median = offsets.sorted()[offsets.count / 2]
        guard abs(median) >= 20 else { return nil }
        let target = roundedToFive(hour * 60 + minute + Int(median.rounded()))
        let wrapped = ((target % 1440) + 1440) % 1440
        let time = Item.clockTimeString(hour: wrapped / 60, minute: wrapped % 60)
        return Suggestion(
            id: "time:\(item.id.uuidString):\(wrapped)",
            itemID: item.persistentModelID,
            message: "You usually do “\(item.title)” around \(time). Move it there?",
            actionLabel: "Move to \(time)",
            action: .moveTime(hour: wrapped / 60, minute: wrapped % 60)
        )
    }

    /// "You often snooze this" — space a repeating routine out, or move a
    /// timed one later, by about how long it usually gets snoozed.
    private static func snoozeSuggestion(_ item: Item, recent: [Occurrence]) -> Suggestion? {
        let snoozed = recent.compactMap { $0.snoozedMinutes }.filter { $0 > 0 }
        guard snoozed.count >= needed else { return nil }
        let average = max(5, roundedToFive(snoozed.reduce(0, +) / snoozed.count))

        switch item.kind {
        case .repeatingRoutine:
            guard let interval = item.intervalSeconds else { return nil }
            let minutes = roundedToFive(Int(interval / 60) + average)
            let label = Item.durationString(Double(minutes * 60))
            return Suggestion(
                id: "space:\(item.id.uuidString):\(minutes)",
                itemID: item.persistentModelID,
                message: "You often snooze “\(item.title)”. Space it out to every \(label)?",
                actionLabel: "Every \(label)",
                action: .setInterval(seconds: Double(minutes * 60))
            )
        case .scheduledRoutine:
            guard let hour = item.hour, let minute = item.minute else { return nil }
            let wrapped = ((roundedToFive(hour * 60 + minute + average) % 1440) + 1440) % 1440
            let time = Item.clockTimeString(hour: wrapped / 60, minute: wrapped % 60)
            return Suggestion(
                id: "later:\(item.id.uuidString):\(wrapped)",
                itemID: item.persistentModelID,
                message: "You often snooze “\(item.title)”. Move it to \(time)?",
                actionLabel: "Move to \(time)",
                action: .moveTime(hour: wrapped / 60, minute: wrapped % 60)
            )
        case .goal:
            return nil
        }
    }

    private static func roundedToFive(_ minutes: Int) -> Int {
        Int((Double(minutes) / 5).rounded()) * 5
    }
}
