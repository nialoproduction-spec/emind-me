import Foundation
import SwiftData

/// Changes to a routine or goal from the panel: pause / resume, edits, and
/// applying a smart suggestion. Each one keeps the stored next-due time and
/// the system notifications in step with the change.
///
/// `reschedule` / `cancelNotifications` default to the real notification
/// service; tests pass no-ops (notifications need an app bundle).
@MainActor
enum ItemActions {
    /// Shortest gap a repeating reminder can have ("every 30 sec" is fine).
    nonisolated static let minimumInterval: TimeInterval = 10


    // MARK: - Pause

    enum PauseLength: String, CaseIterable, Identifiable {
        case oneHour, untilTomorrow, oneWeek, indefinitely
        var id: String { rawValue }

        var label: String {
            switch self {
            case .oneHour: return "For 1 hour"
            case .untilTomorrow: return "Until tomorrow"
            case .oneWeek: return "For 1 week"
            case .indefinitely: return "Until I resume"
            }
        }

        /// When the pause ends; nil = until resumed by hand.
        func endDate(from now: Date, calendar: Calendar = .current) -> Date? {
            switch self {
            case .oneHour:
                return now.addingTimeInterval(3600)
            case .untilTomorrow:
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
                return calendar.date(bySettingHour: 6, minute: 0, second: 0, of: tomorrow) ?? tomorrow
            case .oneWeek:
                return calendar.date(byAdding: .day, value: 7, to: now)
            case .indefinitely:
                return nil
            }
        }
    }

    /// Stops a routine from reminding until `until` (or until resumed).
    /// Anything of its already waiting is set aside, and if its reminder is
    /// on screen, that's closed.
    static func pause(
        _ item: Item,
        until: Date?,
        in context: ModelContext,
        scheduler: ReminderScheduler? = nil,
        cancelNotifications: ((Item) -> Void)? = nil
    ) {
        guard item.kind != .goal else { return }
        let scheduler = scheduler ?? ReminderScheduler.shared
        if let active = scheduler.activeOccurrence,
           active.item?.persistentModelID == item.persistentModelID {
            scheduler.resolveActive(as: .skipped)
        }
        let itemID = item.persistentModelID
        let waiting = (try? context.fetch(FetchDescriptor<Occurrence>())) ?? []
        for occurrence in waiting where occurrence.status == .pending
            && occurrence.item?.persistentModelID == itemID {
            occurrence.status = .skipped
            occurrence.nextEscalationAt = nil
            occurrence.resolvedAt = .now
        }
        item.isActive = false
        item.pausedUntil = until
        item.nextFireDate = nil
        (cancelNotifications ?? { NotificationService.shared.cancel(for: $0) })(item)
        try? context.save()
    }

    static func resume(_ item: Item, now: Date = .now, reschedule: ((Item) -> Void)? = nil) {
        guard item.kind != .goal else { return }
        item.isActive = true
        item.pausedUntil = nil
        // Recompute from now rather than resuming against a stale time.
        item.nextFireDate = item.computeNextFireDate(after: now)
        (reschedule ?? { NotificationService.shared.schedule(for: $0) })(item)
    }

    // MARK: - Edit

    /// The editable fields of an item, as the edit screen fills them in.
    struct Edit: Equatable {
        var title: String
        var category: String?
        var kind: ItemKind
        var intervalSeconds: Double?
        var hour: Int?
        var minute: Int?
        var weekdays: [Int]
        var targetDate: Date?

        init(of item: Item) {
            title = item.title
            category = item.category
            kind = item.kind
            intervalSeconds = item.intervalSeconds
            hour = item.hour
            minute = item.minute
            weekdays = item.weekdaysRaw ?? []
            targetDate = item.targetDate
        }

        /// Whether it can be saved: a title, and a usable schedule.
        var isValid: Bool {
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            switch kind {
            case .repeatingRoutine: return (intervalSeconds ?? 0) >= ItemActions.minimumInterval
            case .scheduledRoutine: return hour != nil && minute != nil
            case .goal: return true
            }
        }
    }

    /// Writes the edit to the item. A changed schedule takes effect from now:
    /// the next reminder is worked out again and notifications re-scheduled.
    static func apply(
        _ edit: Edit,
        to item: Item,
        now: Date = .now,
        reschedule: ((Item) -> Void)? = nil
    ) {
        guard edit.isValid else { return }
        let scheduleChanged = edit.kind != item.kind
            || edit.intervalSeconds != item.intervalSeconds
            || edit.hour != item.hour || edit.minute != item.minute
            || edit.weekdays.sorted() != (item.weekdaysRaw ?? []).sorted()

        item.title = edit.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = edit.category?.trimmingCharacters(in: .whitespacesAndNewlines)
        item.category = (category?.isEmpty ?? true) ? nil : category
        item.kind = edit.kind

        switch edit.kind {
        case .repeatingRoutine:
            item.intervalSeconds = edit.intervalSeconds
            item.hour = nil
            item.minute = nil
            item.weekdaysRaw = nil
            item.targetDate = nil
        case .scheduledRoutine:
            item.intervalSeconds = nil
            item.hour = edit.hour
            item.minute = edit.minute
            let days = Array(Set(edit.weekdays)).sorted()
            item.weekdaysRaw = (days.isEmpty || days.count == 7) ? nil : days
            item.targetDate = nil
        case .goal:
            item.intervalSeconds = nil
            item.hour = nil
            item.minute = nil
            item.weekdaysRaw = nil
            item.targetDate = edit.targetDate
            item.nextFireDate = nil
        }

        if scheduleChanged { item.scheduleEditedAt = now }
        if edit.kind != .goal, scheduleChanged || item.nextFireDate == nil, item.isActive {
            item.nextFireDate = item.computeNextFireDate(after: now)
        }
        // Title changes show in the notification text too, so always refresh.
        (reschedule ?? { NotificationService.shared.schedule(for: $0) })(item)
    }

    // MARK: - Suggestions

    static func apply(
        _ suggestion: Insights.Suggestion,
        to item: Item,
        now: Date = .now,
        reschedule: ((Item) -> Void)? = nil
    ) {
        var edit = Edit(of: item)
        switch suggestion.action {
        case .moveTime(let hour, let minute):
            edit.hour = hour
            edit.minute = minute
        case .setInterval(let seconds):
            edit.intervalSeconds = seconds
        }
        apply(edit, to: item, now: now, reschedule: reschedule)
    }
}

/// Ticking things off (or un-ticking them) in today's checklist.
@MainActor
enum OccurrenceActions {
    /// Sets a checklist entry's status. If it's the reminder on screen, it's
    /// answered through the scheduler, so the card closes as if a button had
    /// been pressed. "Not done" is recorded as missed (`.unfinished`), which
    /// never holds up the routine's next reminder.
    static func set(
        _ occurrence: Occurrence,
        to status: OccurrenceStatus,
        now: Date = .now,
        scheduler: ReminderScheduler? = nil
    ) {
        let scheduler = scheduler ?? ReminderScheduler.shared
        let target: OccurrenceStatus = status == .pending ? .unfinished : status
        if scheduler.activeOccurrence?.id == occurrence.id {
            scheduler.resolveActive(as: target)
            return
        }
        occurrence.status = target
        occurrence.nextEscalationAt = nil
        occurrence.resolvedAt = target == .unfinished ? nil : now
    }

    /// Tapping a checklist row: done ↔ not done.
    static func toggle(_ occurrence: Occurrence, now: Date = .now, scheduler: ReminderScheduler? = nil) {
        set(occurrence, to: occurrence.status == .done ? .unfinished : .done, now: now, scheduler: scheduler)
    }

    /// Removes one entry from the checklist (the routine itself stays).
    static func delete(_ occurrence: Occurrence, in context: ModelContext, scheduler: ReminderScheduler? = nil) {
        let scheduler = scheduler ?? ReminderScheduler.shared
        if scheduler.activeOccurrence?.id == occurrence.id {
            scheduler.resolveActive(as: .skipped)
            // Let the card fade before its record goes.
            Task { @MainActor in
                try? await Task.sleep(for: ItemDeletion.fadeAllowance)
                guard !occurrence.isDeleted else { return }
                context.delete(occurrence)
                try? context.save()
            }
            return
        }
        context.delete(occurrence)
        try? context.save()
    }
}
