import Foundation
import SwiftData
import UserNotifications

/// What the self-check repaired, newest first. Kept so a repair is never silent.
struct RepairLog: Codable, Equatable {
    struct Entry: Codable, Equatable, Identifiable {
        var id = UUID()
        var at: Date
        var text: String
    }

    static let limit = 100
    var entries: [Entry] = []

    mutating func add(_ text: String, at now: Date) {
        entries.insert(Entry(at: now, text: text), at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
    }
}

/// The rules the self-check uses, kept pure so they can be tested without
/// touching notifications.
enum ScheduleAudit {
    /// Should this item have a notification waiting? Active habits that aren't finished.
    static func needsNotification(_ item: Item) -> Bool {
        item.kind != .goal && item.isActive && item.style == .habit && !item.isOver
    }

    /// Items that should have a notification but have none pending. Every
    /// notification for an item uses its id, or its id followed by ".N" for a weekday.
    static func missing(among items: [Item], pending identifiers: [String]) -> [Item] {
        items.filter { item in
            let id = item.id.uuidString
            return needsNotification(item)
                && !identifiers.contains { $0 == id || $0.hasPrefix(id + ".") }
        }
    }
}

/// Checks once a minute that every active reminder still has a notification
/// waiting and that the scheduler's timer is still running. Anything missing
/// is rebuilt and written to the repair log.
@MainActor
final class HealthMonitor {
    static let shared = HealthMonitor()
    static let interval: TimeInterval = 60

    static let log = PersistedSettings<RepairLog>(key: "repairLog", default: RepairLog())
    static let lastCheck = PersistedSettings<Date?>(key: "lastHealthCheck", default: nil)

    private var timer: Timer?
    private var modelContext: ModelContext?

    private init() {}

    func start(modelContext: ModelContext) {
        self.modelContext = modelContext
        timer?.invalidate()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        check()
    }

    /// One pass. Rebuilds whatever is missing; nothing is removed.
    func check(now: Date = .now) {
        if ReminderScheduler.shared.ensureTickRunning() {
            Self.log.value.add("Restarted the reminder timer, which had stopped", at: now)
        }
        guard let modelContext else { return }
        let items = (try? modelContext.fetch(FetchDescriptor<Item>())) ?? []
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let identifiers = requests.map(\.identifier)
            Task { @MainActor in
                self.finishCheck(items: items, pending: identifiers, now: now)
            }
        }
    }

    private func finishCheck(items: [Item], pending: [String], now: Date) {
        for item in ScheduleAudit.missing(among: items, pending: pending) {
            NotificationService.shared.schedule(for: item)
            Self.log.value.add("Rebuilt the missing notification for \"\(item.title)\"", at: now)
        }
        Self.lastCheck.value = now
    }
}
