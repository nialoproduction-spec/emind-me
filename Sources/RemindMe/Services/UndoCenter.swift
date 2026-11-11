import Foundation
import SwiftData

/// The last thing that can be taken back: a delete, a Done or a Skip.
/// ⌘Z in the panel, the "Undo" bar above the add field, or the menu bar's
/// right-click menu. Only the latest one, for 10 minutes.
@MainActor
final class UndoCenter: ObservableObject {
    static let shared = UndoCenter()

    struct Action: Identifiable {
        let id = UUID()
        /// "Deleted “Msg wife”", "Done: Stretch".
        let label: String
        let at: Date
        let perform: @MainActor () -> Void
    }

    /// How long an action can still be undone.
    nonisolated static let window: TimeInterval = 10 * 60

    @Published private(set) var last: Action?
    private let clock: @MainActor () -> Date

    init(now: (@MainActor () -> Date)? = nil) {
        clock = now ?? { Date.now }
    }

    func record(_ label: String, perform: @escaping @MainActor () -> Void) {
        last = Action(label: label, at: clock(), perform: perform)
    }

    /// What ⌘Z would undo right now, if anything.
    var available: Action? {
        guard let last, clock().timeIntervalSince(last.at) <= Self.window else { return nil }
        return last
    }

    /// Undoes the last action. False if there was nothing (or it's too old).
    @discardableResult
    func undoLast() -> Bool {
        guard let action = available else { last = nil; return false }
        last = nil
        action.perform()
        return true
    }

    func clear() { last = nil }
}
