import AppKit
import Carbon.HIToolbox

/// One key with modifiers, such as ⌥D. Saved so it can be changed in Settings.
struct KeyBinding: Codable, Equatable {
    /// Virtual key code: the same numbers Carbon and AppKit use.
    var keyCode: UInt16
    /// NSEvent.ModifierFlags raw value, limited to ⌃ ⌥ ⇧ ⌘.
    var modifiers: UInt
    /// The letter shown, e.g. "D".
    var key: String

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    /// Symbols in the usual macOS order, then the key: "⌥D", "⌃⇧⌘K".
    var display: String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + key
    }

    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    static func option(_ key: String, code: Int) -> KeyBinding {
        KeyBinding(keyCode: UInt16(code), modifiers: NSEvent.ModifierFlags.option.rawValue, key: key)
    }
}

/// The key that, held on its own, starts a voice note.
enum TalkKey: String, Codable, CaseIterable, Identifiable {
    case option, command, control

    var id: String { rawValue }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .option: .option
        case .command: .command
        case .control: .control
        }
    }

    var title: String {
        switch self {
        case .option: "Option (⌥)"
        case .command: "Command (⌘)"
        case .control: "Control (⌃)"
        }
    }
}

/// Every shortcut the app listens for. Changed in Settings → Smart.
struct KeyBindings: Codable, Equatable {
    enum Action: String, Codable, CaseIterable, Identifiable {
        case done, snooze, skip, undo

        var id: String { rawValue }

        var title: String {
            switch self {
            case .done: "Done"
            case .snooze: "Snooze"
            case .skip: "Skip"
            case .undo: "Undo"
            }
        }

        /// Undo works any time; the others only while a reminder is on screen.
        var needsReminder: Bool { self != .undo }
    }

    var done = KeyBinding.option("D", code: kVK_ANSI_D)
    var snooze = KeyBinding.option("S", code: kVK_ANSI_S)
    var skip = KeyBinding.option("K", code: kVK_ANSI_K)
    var undo = KeyBinding.option("Z", code: kVK_ANSI_Z)
    var talk: TalkKey = .option

    subscript(action: Action) -> KeyBinding {
        get {
            switch action {
            case .done: done
            case .snooze: snooze
            case .skip: skip
            case .undo: undo
            }
        }
        set {
            switch action {
            case .done: done = newValue
            case .snooze: snooze = newValue
            case .skip: skip = newValue
            case .undo: undo = newValue
            }
        }
    }

    /// The other action already using this exact key, if any.
    func conflict(for binding: KeyBinding, except action: Action) -> Action? {
        Action.allCases.first { other in
            other != action && self[other].keyCode == binding.keyCode && self[other].modifiers == binding.modifiers
        }
    }

    @MainActor
    static let store = PersistedSettings<KeyBindings>(key: "keyBindings", default: KeyBindings())
}

extension KeyBindings.Action {
    init(_ action: ReminderScheduler.ShortcutAction) {
        switch action {
        case .done: self = .done
        case .snooze: self = .snooze
        case .skip: self = .skip
        }
    }
}
