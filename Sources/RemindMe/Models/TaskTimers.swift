import Foundation

/// A timed task: "choosing music within 30 min". It counts down. At zero it asks
/// whether you're done. If nobody answers for a minute it turns red and counts on.
/// Kept apart from SwiftData, so its states never touch the reminder rules.
struct TaskTimers: Codable, Equatable {
    enum State: String, Codable, Equatable {
        case running, asking, overdue, done, queued
    }

    struct Entry: Codable, Equatable, Identifiable {
        var id = UUID()
        var title: String
        var category: String?
        var seconds: Double
        var startedAt: Date
        var state: State = .running
        /// When it reached zero and asked.
        var askedAt: Date?

        var endsAt: Date { startedAt.addingTimeInterval(seconds) }
    }

    struct Transitions: Equatable {
        var asking: [Entry] = []
        var overdue: [Entry] = []
        var isEmpty: Bool { asking.isEmpty && overdue.isEmpty }
    }

    /// How long a question can wait unanswered before the timer turns red.
    static let patience: TimeInterval = 60
    /// Finished timers kept for reference; open ones are never dropped.
    static let keepFinished = 20

    var entries: [Entry] = []

    var open: [Entry] { entries.filter { $0.state != .done } }

    /// The timer on the notch now: the first that isn't finished or waiting.
    var current: Entry? {
        entries.first { $0.state == .running || $0.state == .asking || $0.state == .overdue }
    }

    /// Timers run one after another. A new one waits behind any that's still going.
    mutating func start(title: String, category: String?, seconds: Double, at now: Date) {
        let busy = current != nil
        entries.insert(Entry(title: title, category: category, seconds: seconds, startedAt: now,
                             state: busy ? .queued : .running), at: 0)
        let finished = entries.filter { $0.state == .done }
        if finished.count > Self.keepFinished, let oldest = finished.last {
            entries.removeAll { $0.id == oldest.id }
        }
    }

    /// Moves timers along with the clock. Returns only what changed.
    mutating func advance(now: Date) -> Transitions {
        var result = Transitions()
        for index in entries.indices {
            switch entries[index].state {
            case .running where now >= entries[index].endsAt:
                entries[index].state = .asking
                entries[index].askedAt = now
                result.asking.append(entries[index])
            case .asking where now.timeIntervalSince(entries[index].askedAt ?? now) >= Self.patience:
                entries[index].state = .overdue
                result.overdue.append(entries[index])
            default:
                break
            }
        }
        return result
    }

    /// Done: the oldest queued timer starts now.
    mutating func markDone(_ id: UUID, now: Date = .now) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].state = .done
        guard current == nil, let next = entries.lastIndex(where: { $0.state == .queued }) else { return }
        entries[next].state = .running
        entries[next].startedAt = now
    }

    /// "Not yet": it keeps counting on, now in red.
    mutating func notYet(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }), entries[index].state != .done else { return }
        entries[index].state = .overdue
    }

    /// "12:05" or "1:02:05".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// The shared store the app reads and writes.
    @MainActor
    static let store = PersistedSettings<TaskTimers>(key: "taskTimers", default: TaskTimers())

    @MainActor
    static func start(_ request: TimerRequest, category: String?, now: Date = .now) {
        var timers = store.value
        timers.start(title: request.title, category: category ?? request.category, seconds: request.seconds, at: now)
        store.value = timers
    }

    @MainActor
    static func markDone(_ id: UUID) {
        var timers = store.value
        timers.markDone(id, now: .now)
        store.value = timers
    }

    @MainActor
    static func notYet(_ id: UUID) {
        var timers = store.value
        timers.notYet(id)
        store.value = timers
    }
}

/// A timer the parser found in the text.
struct TimerRequest: Equatable {
    var title: String
    var seconds: Double
    var category: String?
}

extension TimerRequest {
    /// Reads "<task> [with] [within|in|for] N min|hours" at the end of the text.
    /// Phrases that are reminders ("remind me…", "every…", "at 4pm", "in 2 hours"
    /// on its own) return nil and go to the normal parser.
    static func parse(_ text: String) -> TimerRequest? {
        let lower = text.lowercased()
        let reminderWords = ["every", " at ", "tomorrow", "remind", "today", "tonight", "daily", "weekly"]
        guard !reminderWords.contains(where: { lower.contains($0) }) else { return nil }

        let ns = text as NSString
        guard let match = timerRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let rawTask = ns.substring(with: match.range(withName: "task")).trimmingCharacters(in: .whitespaces)
        guard rawTask.count >= 2, !["in", "within", "for", "with"].contains(rawTask.lowercased()) else { return nil }
        guard let quantity = ItemParser.parseQuantity(ns.substring(with: match.range(withName: "qty"))),
              quantity > 0 else { return nil }
        let unit = ns.substring(with: match.range(withName: "unit")).lowercased()
        // "in 2 hours" on its own is a one-time reminder, not a timer.
        let prepRange = match.range(withName: "prep")
        let prep = prepRange.location == NSNotFound ? "" : ns.substring(with: prepRange).lowercased()
        if prep == "in", unit.hasPrefix("h") { return nil }
        let seconds = quantity * ItemParser.unitSeconds(unit)

        let title = rawTask.prefix(1).uppercased() + rawTask.dropFirst()
        return TimerRequest(title: title, seconds: seconds, category: category(for: title))
    }

    /// Several timers in one line: "edit song 2 min, write 3 song", split on
    /// commas, periods, " - " or " and ". Every part must be a timer, or the
    /// whole line is left to the normal parser (returns []).
    static func parseAll(_ text: String) -> [TimerRequest] {
        let ns = text as NSString
        var pieces: [String] = []
        var last = 0
        for match in splitRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            pieces.append(ns.substring(with: NSRange(location: last, length: match.range.location - last)))
            last = match.range.location + match.range.length
        }
        pieces.append(ns.substring(from: last))
        let cleaned = pieces.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard cleaned.count > 1 else { return [] }
        var requests: [TimerRequest] = []
        for piece in cleaned {
            guard let request = parse(piece) else { return [] }
            requests.append(request)
        }
        return requests
    }

    private static let splitRegex = try! NSRegularExpression(
        pattern: #"\s*(?:,|\.(?=\s|$)|\s-\s|\s+and\s+)\s*"#,
        options: [.caseInsensitive])

    private static let timerRegex = try! NSRegularExpression(
        pattern: #"^\s*(?<task>.*?[a-z].*?)\s+(?:with\s+)?(?:(?<prep>within|in|for)\s+)?(?<qty>\d+(?:\.\d+)?)\s*(?<unit>minutes?|mins?|hours?|hrs?)\s*$"#,
        options: [.caseInsensitive])

    /// A category from the task's words, so "editing" and "color grading" group together.
    static func category(for title: String) -> String? {
        let words = title.lowercased()
        let map: [(String, String)] = [
            ("edit", "Editing"), ("colo", "Grading"), ("grad", "Grading"),
            ("file", "Files"), ("export", "Export"), ("render", "Export"),
            ("music", "Music"), ("song", "Music"),
        ]
        return map.first { words.contains($0.0) }?.1
    }
}
