import Foundation
import SwiftData

/// Goals are answered once a day: Done or Not today. Each answer is stored
/// as an ordinary `Occurrence` of the goal (done / skipped), so totals,
/// streaks and history work the same way as for habits. Answers are never
/// `.pending`, so they never block or nag anything (rule 4).
@MainActor
enum GoalCheckIn {
    /// Today's answer for a goal, if there is one.
    static func todaysAnswer(for goal: Item, in occurrences: [Occurrence], now: Date,
                             calendar: Calendar = .current) -> Occurrence? {
        let key = Occurrence.dayKey(for: now, calendar: calendar)
        return Insights.occurrences(of: goal, in: occurrences).first { $0.dayKey == key }
    }

    /// Goals still waiting for today's answer: not finished for good, and
    /// not answered yet today. Oldest first.
    static func unanswered(goals: [Item], occurrences: [Occurrence], now: Date,
                           calendar: Calendar = .current) -> [Item] {
        goals
            .filter { $0.kind == .goal && !$0.isAchieved }
            .filter { todaysAnswer(for: $0, in: occurrences, now: now, calendar: calendar) == nil }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Records Done or Not today, replacing an earlier answer from today.
    @discardableResult
    static func answer(_ goal: Item, done: Bool, now: Date, in context: ModelContext,
                       calendar: Calendar = .current) -> Occurrence {
        let all = (try? context.fetch(FetchDescriptor<Occurrence>())) ?? []
        let entry: Occurrence
        if let existing = todaysAnswer(for: goal, in: all, now: now, calendar: calendar) {
            entry = existing
        } else {
            entry = Occurrence(item: goal, scheduledFireDate: now, calendar: calendar)
            entry.firstFiredAt = now
            context.insert(entry)
        }
        entry.status = done ? .done : .skipped
        entry.nextEscalationAt = nil
        entry.resolvedAt = now
        try? context.save()
        return entry
    }
}
