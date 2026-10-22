import Foundation

/// The life of each reminder, step by step: it came due (fired), it appeared
/// on screen (shown), you answered it (acknowledged), or it went unanswered or
/// unseen (missed, or unfinished after its last nag). Newest first, so you can
/// check at a glance that nothing was lost.
struct DeliveryLog: Codable, Equatable {
    enum Step: String, Codable, Equatable {
        case fired, shown, acknowledged, missed, unfinished

        var label: String {
            switch self {
            case .fired: "Due"
            case .shown: "Shown"
            case .acknowledged: "Answered"
            case .missed: "Missed"
            case .unfinished: "Unfinished"
            }
        }
    }

    struct Entry: Codable, Equatable, Identifiable {
        var id = UUID()
        var at: Date
        var title: String
        var step: Step
        var detail: String? = nil
    }

    static let limit = 500
    var entries: [Entry] = []

    mutating func add(_ step: Step, title: String, at now: Date, detail: String? = nil) {
        entries.insert(Entry(at: now, title: title, step: step, detail: detail), at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
    }

    /// The log the app writes to.
    @MainActor
    static let store = PersistedSettings<DeliveryLog>(key: "deliveryLog", default: DeliveryLog())

    @MainActor
    static func record(_ step: Step, title: String, at now: Date, detail: String? = nil) {
        store.value.add(step, title: title, at: now, detail: detail)
    }
}
