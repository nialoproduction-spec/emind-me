import Foundation
@preconcurrency import UserNotifications

/// Local notifications only — nothing leaves the device. Goals never get a
/// notification at all, by design: they're tracked, not scheduled.
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private init() {}

    func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    /// Replaces any existing schedule for this item with a fresh one that
    /// matches its current kind and settings.
    func schedule(for item: Item) {
        cancel(for: item)
        // Reminders use the little popup instead (no duplicate banner).
        guard item.kind != .goal, item.isActive, item.style == .habit else { return }

        switch item.kind {
        case .repeatingRoutine:
            scheduleRepeating(item)
        case .scheduledRoutine:
            scheduleClockTime(item)
        case .goal:
            break
        }
    }

    func cancel(for item: Item) {
        let center = UNUserNotificationCenter.current()
        var identifiers = [item.id.uuidString]
        identifiers += (1...7).map { "\(item.id.uuidString).\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func scheduleRepeating(_ item: Item) {
        guard let interval = item.intervalSeconds, interval >= 60 else { return }
        let content = makeContent(for: item)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: true)
        let request = UNNotificationRequest(identifier: item.id.uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func scheduleClockTime(_ item: Item) {
        guard let hour = item.hour, let minute = item.minute, !item.isOver else { return }
        let content = makeContent(for: item)
        let weekdays = item.weekdaysRaw ?? []

        // One-time, monthly, yearly: one trigger each.
        var special: (DateComponents, Bool)?
        switch item.repeatKind {
        case .once:
            guard let onceAt = item.onceAt, onceAt > .now else { return }
            special = (Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: onceAt), false)
        case .monthly:
            special = (DateComponents(day: item.monthDay, hour: hour, minute: minute), true)
        case .yearly:
            special = (DateComponents(month: item.yearMonth, day: item.monthDay, hour: hour, minute: minute), true)
        case .deadline:
            return // deadlines use the little popup
        case .daily, .weekly:
            break
        }
        if let special {
            let trigger = UNCalendarNotificationTrigger(dateMatching: special.0, repeats: special.1)
            let request = UNNotificationRequest(identifier: item.id.uuidString, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
            return
        }

        if weekdays.isEmpty {
            var comps = DateComponents()
            comps.hour = hour
            comps.minute = minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let request = UNNotificationRequest(identifier: item.id.uuidString, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        } else {
            for weekday in weekdays {
                var comps = DateComponents()
                comps.hour = hour
                comps.minute = minute
                comps.weekday = weekday
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                let request = UNNotificationRequest(
                    identifier: "\(item.id.uuidString).\(weekday)", content: content, trigger: trigger
                )
                UNUserNotificationCenter.current().add(request)
            }
        }
    }

    private func makeContent(for item: Item) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.kind == .repeatingRoutine ? "Time for your routine" : "Reminder"
        content.sound = nil // silent, by choice
        return content
    }
}
