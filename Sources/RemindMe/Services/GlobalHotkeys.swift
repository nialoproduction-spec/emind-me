import AppKit
import Carbon.HIToolbox
import Combine

/// System-wide shortcuts. Done, Snooze and Skip answer the reminder on screen,
/// so they're registered only while one is showing. Undo works any time. The
/// keys are whatever Settings → Smart holds (default: Option plus a letter).
/// Uses the system hot-key service, so no Accessibility permission is needed.
@MainActor
final class GlobalHotkeys {
    static let shared = GlobalHotkeys()

    /// "RMND"
    private static let signature: OSType = 0x524D_4E44

    static func label(for action: ReminderScheduler.ShortcutAction) -> String {
        KeyBindings.store.value[KeyBindings.Action(action)].display
    }

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?
    private var subscriptions: [AnyCancellable] = []

    private init() {}

    func start() {
        installHandler()
        subscriptions = [
            ReminderScheduler.shared.$activeOccurrence
                .map { $0 != nil }
                .removeDuplicates()
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.refresh() },
            AppSettings.smart.$value
                .map(\.globalShortcuts)
                .removeDuplicates()
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.refresh() },
            KeyBindings.store.$value
                .removeDuplicates()
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.refresh() },
        ]
        refresh()
    }

    private func refresh() {
        unregister()
        guard AppSettings.smart.value.globalShortcuts else { return }
        let reminderShowing = ReminderScheduler.shared.activeOccurrence != nil
        for (index, action) in KeyBindings.Action.allCases.enumerated() {
            guard !action.needsReminder || reminderShowing else { continue }
            let binding = KeyBindings.store.value[action]
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index + 1))
            let status = RegisterEventHotKey(UInt32(binding.keyCode), binding.carbonModifiers, id,
                                             GetApplicationEventTarget(), 0, &ref)
            // Taken by another app: skip that one, keep the others.
            if status == noErr, let ref { hotKeyRefs.append(ref) }
        }
    }

    private func unregister() {
        for ref in hotKeyRefs { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeAll()
    }

    private func installHandler() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &spec, nil, &handlerRef)
    }

    /// Ids are 1-based positions in `KeyBindings.Action.allCases`, as registered in `refresh`.
    fileprivate static func handle(id: UInt32) {
        let actions = KeyBindings.Action.allCases
        guard id >= 1, Int(id) <= actions.count else { return }
        switch actions[Int(id) - 1] {
        case .undo: _ = UndoCenter.shared.undoLast()
        case .done: ReminderScheduler.shared.requestShortcut(.done)
        case .snooze: ReminderScheduler.shared.requestShortcut(.snooze)
        case .skip: ReminderScheduler.shared.requestShortcut(.skip)
        }
    }
}

/// Called by the system when one of the hot keys is pressed. A plain C
/// callback (no captured state), so it lives outside the class.
private let hotKeyEventHandler: EventHandlerUPP = { _, event, _ -> OSStatus in
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
    )
    guard status == noErr else { return status }
    let id = hotKeyID.id
    DispatchQueue.main.async {
        MainActor.assumeIsolated { GlobalHotkeys.handle(id: id) }
    }
    return noErr
}
