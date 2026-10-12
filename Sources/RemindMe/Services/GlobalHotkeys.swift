import AppKit
import Carbon.HIToolbox
import Combine

/// System-wide shortcuts for the reminder on screen — ⌃⌥D Done, ⌃⌥S Snooze,
/// ⌃⌥K Skip — so it can be answered without reaching for the mouse or
/// leaving the app you're in.
///
/// They're registered only while a reminder is showing (and released right
/// after), so they never block those keys in other apps the rest of the
/// time. Uses the system hot-key service, which needs no Accessibility
/// permission and never sees any other keystrokes.
@MainActor
final class GlobalHotkeys {
    static let shared = GlobalHotkeys()

    struct Binding {
        let id: UInt32
        let keyCode: UInt32
        let key: String
        let action: ReminderScheduler.ShortcutAction
    }

    static let bindings: [Binding] = [
        Binding(id: 1, keyCode: UInt32(kVK_ANSI_D), key: "D", action: .done),
        Binding(id: 2, keyCode: UInt32(kVK_ANSI_S), key: "S", action: .snooze),
        Binding(id: 3, keyCode: UInt32(kVK_ANSI_K), key: "K", action: .skip),
    ]
    static let modifiers = UInt32(controlKey | optionKey)
    static let modifierSymbols = "⌃⌥"
    /// "RMND"
    private static let signature: OSType = 0x524D_4E44

    static func label(for action: ReminderScheduler.ShortcutAction) -> String {
        guard let binding = bindings.first(where: { $0.action == action }) else { return "" }
        return modifierSymbols + binding.key
    }

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?
    private var subscription: AnyCancellable?
    private var settingsSubscription: AnyCancellable?

    private init() {}

    func start() {
        installHandler()
        let scheduler = ReminderScheduler.shared
        subscription = scheduler.$activeOccurrence
            .map { $0 != nil }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
        settingsSubscription = AppSettings.smart.$value
            .map(\.globalShortcuts)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
    }

    private func refresh() {
        let wanted = ReminderScheduler.shared.activeOccurrence != nil && AppSettings.smart.value.globalShortcuts
        if wanted { register() } else { unregister() }
    }

    private func register() {
        guard hotKeyRefs.isEmpty else { return }
        for binding in Self.bindings {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: binding.id)
            let status = RegisterEventHotKey(binding.keyCode, Self.modifiers, id,
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
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
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
        }, 1, &spec, nil, &handlerRef)
    }

    private static func handle(id: UInt32) {
        guard let binding = bindings.first(where: { $0.id == id }) else { return }
        ReminderScheduler.shared.requestShortcut(binding.action)
    }
}
