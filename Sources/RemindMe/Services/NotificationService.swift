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
        guard item.kind != .goal, item.isActive else { return }

        switch item.kind {
        case .repeatingRoutine:
            scheduleRepeating(item)
        case .scheduledRoutine:
            scheduleClockTime(item)
        case .goal:
            break
        }
    }

    /// A one-off banner right now (the break timer uses this). No sound: the
    /// caller plays its own beep.
    func postNow(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
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
        guard let hour = item.hour, let minute = item.minute else { return }
        let content = makeContent(for: item)
        let weekdays = item.weekdaysRaw ?? []

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
        content.sound = .default
        return content
    }
}
