import Foundation
import SwiftData

/// One concrete firing of a routine — the actual "reminder" that pops the
/// panel. Separate from `Item` because a routine fires many times (an
/// interval routine fires repeatedly all day); each firing needs its own
/// done / skip / escalation state and its own slot in the daily checklist.
/// Goals never produce occurrences — they're never alerted.
enum OccurrenceStatus: Int, Codable {
    case pending = 0
    case done = 1
    case skipped = 2
    /// Escalation ran out (N unanswered pops, N set in Settings) — moved to the day's
    /// unfinished list instead of continuing to nag.
    case unfinished = 3
}

@Model
final class Occurrence {
    var id: UUID
    var item: Item?
    /// "yyyy-MM-dd" in the local calendar — groups this into a day's
    /// checklist regardless of exactly when during the day it fired.
    var dayKey: String
    var scheduledFireDate: Date
    var statusRaw: Int
    /// How many times the panel has popped for this occurrence (max set in Settings).
    var remindersSentCount: Int
    var firstFiredAt: Date?
    /// Absolute time of the next nag. Nil once resolved (done/skipped) or
    /// once escalation is exhausted (unfinished).
    var nextEscalationAt: Date?
    var resolvedAt: Date?

    var status: OccurrenceStatus {
        get { OccurrenceStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        item: Item?,
        scheduledFireDate: Date,
        calendar: Calendar = .current
    ) {
        self.id = id
        self.item = item
        self.scheduledFireDate = scheduledFireDate
        self.dayKey = Self.dayKey(for: scheduledFireDate, calendar: calendar)
        self.statusRaw = OccurrenceStatus.pending.rawValue
        self.remindersSentCount = 0
        self.firstFiredAt = nil
        self.nextEscalationAt = nil
        self.resolvedAt = nil
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }
}
