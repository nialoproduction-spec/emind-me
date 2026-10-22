import AppKit
import Foundation
import SwiftData
import UniformTypeIdentifiers

/// One file with every reminder, habit, goal and deadline and all their
/// history, as plain JSON. Made by hand (Settings → Smart → Backup) and once
/// a day by itself (the last 7 are kept). Restoring adds back whatever isn't
/// already there, so it never wipes anything. Also how a deleted item comes
/// back on ⌘Z.
enum Backup {
    static let version = 1

    struct ItemRecord: Codable, Equatable {
        var id: UUID
        var title: String
        var kindRaw: Int
        var createdAt: Date
        var isActive: Bool
        var isAchieved: Bool
        var intervalSeconds: Double?
        var hour: Int?
        var minute: Int?
        var weekdaysRaw: [Int]?
        var targetDate: Date?
        var nextFireDate: Date?
        var pausedUntil: Date?
        var category: String?
        var scheduleEditedAt: Date?
        var styleRaw: Int?
        var onceAt: Date?
        var monthDay: Int?
        var yearMonth: Int?
        var dueDate: Date?
        var endedAt: Date?

        init(_ item: Item) {
            id = item.id
            title = item.title
            kindRaw = item.kindRaw
            createdAt = item.createdAt
            isActive = item.isActive
            isAchieved = item.isAchieved
            intervalSeconds = item.intervalSeconds
            hour = item.hour
            minute = item.minute
            weekdaysRaw = item.weekdaysRaw
            targetDate = item.targetDate
            nextFireDate = item.nextFireDate
            pausedUntil = item.pausedUntil
            category = item.category
            scheduleEditedAt = item.scheduleEditedAt
            styleRaw = item.styleRaw
            onceAt = item.onceAt
            monthDay = item.monthDay
            yearMonth = item.yearMonth
            dueDate = item.dueDate
            endedAt = item.endedAt
        }

        func makeItem() -> Item {
            let item = Item(id: id, title: title, kind: ItemKind(rawValue: kindRaw) ?? .goal, createdAt: createdAt,
                            isActive: isActive, isAchieved: isAchieved, intervalSeconds: intervalSeconds,
                            hour: hour, minute: minute, weekdaysRaw: weekdaysRaw, targetDate: targetDate,
                            nextFireDate: nextFireDate, category: category)
            item.kindRaw = kindRaw
            item.pausedUntil = pausedUntil
            item.scheduleEditedAt = scheduleEditedAt
            item.styleRaw = styleRaw
            item.onceAt = onceAt
            item.monthDay = monthDay
            item.yearMonth = yearMonth
            item.dueDate = dueDate
            item.endedAt = endedAt
            return item
        }
    }

    struct OccurrenceRecord: Codable, Equatable {
        var id: UUID
        var itemID: UUID?
        var dayKey: String
        var scheduledFireDate: Date
        var statusRaw: Int
        var remindersSentCount: Int
        var firstFiredAt: Date?
        var nextEscalationAt: Date?
        var resolvedAt: Date?
        var snoozedMinutes: Int?

        init(_ occurrence: Occurrence) {
            id = occurrence.id
            itemID = occurrence.item?.id
            dayKey = occurrence.dayKey
            scheduledFireDate = occurrence.scheduledFireDate
            statusRaw = occurrence.statusRaw
            remindersSentCount = occurrence.remindersSentCount
            firstFiredAt = occurrence.firstFiredAt
            nextEscalationAt = occurrence.nextEscalationAt
            resolvedAt = occurrence.resolvedAt
            snoozedMinutes = occurrence.snoozedMinutes
        }

        func makeOccurrence(item: Item?) -> Occurrence {
            let occurrence = Occurrence(id: id, item: item, scheduledFireDate: scheduledFireDate)
            occurrence.dayKey = dayKey
            occurrence.statusRaw = statusRaw
            occurrence.remindersSentCount = remindersSentCount
            occurrence.firstFiredAt = firstFiredAt
            occurrence.nextEscalationAt = nextEscalationAt
            occurrence.resolvedAt = resolvedAt
            occurrence.snoozedMinutes = snoozedMinutes
            return occurrence
        }
    }

    struct File: Codable, Equatable {
        var version = Backup.version
        var createdAt: Date
        var items: [ItemRecord]
        var occurrences: [OccurrenceRecord]
    }

    // MARK: - Making and restoring

    @MainActor
    static func make(from context: ModelContext, now: Date = .now) -> File {
        let items = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        let occurrences = (try? context.fetch(FetchDescriptor<Occurrence>())) ?? []
        return File(createdAt: now, items: items.map(ItemRecord.init),
                    occurrences: occurrences.filter { $0.item != nil }.map(OccurrenceRecord.init))
    }

    /// Just one item and its history (for undoing a delete).
    @MainActor
    static func make(of item: Item, from context: ModelContext, now: Date = .now) -> File {
        let id = item.persistentModelID
        let occurrences = (try? context.fetch(FetchDescriptor<Occurrence>())) ?? []
        return File(createdAt: now, items: [ItemRecord(item)],
                    occurrences: occurrences.filter { $0.item?.persistentModelID == id }.map(OccurrenceRecord.init))
    }

    /// Adds back what isn't there yet (matched by id); nothing is replaced
    /// or removed. Returns how many items and history entries came back.
    @MainActor
    @discardableResult
    static func restore(_ file: File, into context: ModelContext) -> (items: Int, entries: Int) {
        var existingItems: [UUID: Item] = [:]
        for item in (try? context.fetch(FetchDescriptor<Item>())) ?? [] { existingItems[item.id] = item }
        let existingOccurrences = Set(((try? context.fetch(FetchDescriptor<Occurrence>())) ?? []).map(\.id))

        var addedItems = 0
        for record in file.items where existingItems[record.id] == nil {
            let item = record.makeItem()
            context.insert(item)
            existingItems[record.id] = item
            addedItems += 1
        }
        var addedEntries = 0
        for record in file.occurrences where !existingOccurrences.contains(record.id) {
            guard let itemID = record.itemID, let item = existingItems[itemID] else { continue }
            context.insert(record.makeOccurrence(item: item))
            addedEntries += 1
        }
        try? context.save()
        return (addedItems, addedEntries)
    }

    // MARK: - Files

    /// Readable dates, to the millisecond (so nothing shifts on a round trip).
    static func encode(_ file: File) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.dateFormatter(fractional: true).string(from: date))
        }
        return try encoder.encode(file)
    }

    static func decode(_ data: Data) throws -> File {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = Self.dateFormatter(fractional: true).date(from: text)
                ?? Self.dateFormatter(fractional: false).date(from: text) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a date: \(text)")
        }
        return try decoder.decode(File.self, from: data)
    }

    private static func dateFormatter(fractional: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return formatter
    }

    /// ~/Library/Application Support/Remind Me/Backups
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Remind Me/Backups", isDirectory: true)
    }

    static func fileName(for date: Date) -> String {
        "Remind Me backup \(Occurrence.dayKey(for: date)).json"
    }

    /// The day's automatic backup, once a day; keeps the newest `keep`.
    @MainActor
    static func autoSave(from context: ModelContext, now: Date = .now, keep: Int = 7,
                         folder: URL = Backup.folder) {
        let fm = FileManager.default
        let url = folder.appendingPathComponent(fileName(for: now))
        guard !fm.fileExists(atPath: url.path) else { return }
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try encode(make(from: context, now: now)).write(to: url, options: .atomic)
        } catch {
            return
        }
        let backups = ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasPrefix("Remind Me backup ") && $0.hasSuffix(".json") }
            .sorted()
        for name in backups.dropLast(keep) {
            try? fm.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    // MARK: - Save / open panels

    /// "Back up…": asks where, then writes the file.
    @MainActor
    static func exportWithPanel(from context: ModelContext) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileName(for: .now)
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? encode(make(from: context)).write(to: url, options: .atomic)
    }

    /// "Restore…": pick a backup file; returns what came back, or nil.
    @MainActor
    static func importWithPanel(into context: ModelContext) -> (items: Int, entries: Int)? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url), let file = try? decode(data) else { return nil }
        let result = restore(file, into: context)
        for item in (try? context.fetch(FetchDescriptor<Item>())) ?? [] where item.isActive {
            NotificationService.shared.schedule(for: item)
        }
        return result
    }
}
