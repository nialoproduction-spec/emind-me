import Foundation

/// Reminders that have popped up (or were missed while you were away) and
/// wait at the bottom of the panel for a ✓, so nothing set is forgotten.
/// One entry per reminder: a deadline that nudges again replaces its entry.
struct TickList: Codable, Equatable {
    struct Entry: Codable, Equatable, Identifiable {
        var id = UUID()
        var itemID: UUID?
        var title: String
        var at: Date
        /// It came due while you were away or the Mac was asleep.
        var missed = false
    }

    static let limit = 100
    var entries: [Entry] = []

    mutating func add(itemID: UUID?, title: String, at date: Date, missed: Bool = false) {
        if let itemID { entries.removeAll { $0.itemID == itemID } }
        entries.insert(Entry(itemID: itemID, title: title, at: date, missed: missed), at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
    }

    /// Ticked: it's done, it leaves the list.
    mutating func tick(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    /// Its reminder was deleted: nothing left to tick.
    mutating func forget(itemID: UUID) {
        entries.removeAll { $0.itemID == itemID }
    }
}

extension AppSettings {
    static let toTick = PersistedSettings(key: "toTick.v1", default: TickList())
}
