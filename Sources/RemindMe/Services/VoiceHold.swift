import AppKit

/// Hold the talk key (Option by default) on its own to talk. The panel opens,
/// speech fills the add box, and letting go stops listening. Nothing is saved:
/// the usual preview shows what the reminder will be, and you press Save.
///
/// Watching modifier keys from other apps needs the Input Monitoring permission.
/// macOS asks for it the first time.
@MainActor
final class VoiceHold {
    static let shared = VoiceHold()

    /// What a key event means for the hold, extracted before leaving the
    /// event callback.
    enum Input {
        case modifiers(NSEvent.ModifierFlags)
        case key
    }

    private var hold = CommandHold()
    private var monitors: [Any] = []
    private var tick: Task<Void, Never>?
    private var wantsListening = false
    private var baseText = ""

    private init() {}

    func start() {
        guard monitors.isEmpty else { return }
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            let input = Self.input(for: event)
            Task { @MainActor in VoiceHold.shared.handle(input) }
        }
        // Global monitors don't see this app's own windows, so the panel needs a local one too.
        let local = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            let input = Self.input(for: event)
            Task { @MainActor in VoiceHold.shared.handle(input) }
            return event
        }
        monitors = [global, local].compactMap { $0 }
    }

    nonisolated static func input(for event: NSEvent) -> Input {
        if event.type == .keyDown { return .key }
        return .modifiers(event.modifierFlags.intersection(.deviceIndependentFlagsMask))
    }

    private func handle(_ input: Input) {
        switch input {
        case .key:
            hold.otherKeyPressed()
        case .modifiers(let flags):
            // Only the talk key is down: no other modifier, and no key since.
            let talk = KeyBindings.store.value.talk.flag
            let onlyTalk = flags.contains(talk)
                && flags.intersection([.command, .option, .control, .shift, .function]) == talk
            if let event = hold.modifiersChanged(commandOnly: onlyTalk, at: .now) {
                apply(event)
            }
            if onlyTalk { scheduleTick() } else { tick?.cancel() }
        }
    }

    /// Checks again once the threshold has passed, in case the talk key is still held alone.
    private func scheduleTick() {
        tick?.cancel()
        tick = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(CommandHold.threshold * 1000)))
            guard !Task.isCancelled else { return }
            if let event = hold.tick(at: .now) { apply(event) }
        }
    }

    private func apply(_ event: CommandHold.Event) {
        switch event {
        case .begin:
            wantsListening = true
            VoiceInput.shared.authorise { [weak self] allowed in
                // Only start if the key is still held when permission comes back.
                guard allowed, self?.wantsListening == true else { return }
                self?.startRecording()
            }
        case .end:
            wantsListening = false
            stopRecording()
        }
    }

    private func startRecording() {
        baseText = PanelDraft.shared.text
        let panel = ReminderPanelController.shared
        panel.show()
        panel.setExpanded(true)
        panel.keepOpenUntilClickAway()
        VoiceInput.shared.start { [weak self] heard in
            guard let self else { return }
            PanelDraft.shared.text = [self.baseText.trimmingCharacters(in: .whitespaces), heard]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
    }

    private func stopRecording() {
        VoiceInput.shared.stop()
    }
}
