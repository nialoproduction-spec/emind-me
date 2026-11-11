import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A button that shows a shortcut. Click it, press the new keys, and it's
/// saved. Escape cancels. Keys need at least one of ⌘ ⌥ ⌃ ⇧, so a plain
/// letter can't be taken over.
struct ShortcutRecorder: View {
    let binding: KeyBinding
    let onRecord: (KeyBinding) -> Void

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Press keys… (Esc to cancel)" : binding.display) {
            recording ? stop() : start()
        }
        .buttonStyle(.bordered)
        .font(.system(.callout, design: .monospaced))
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
                return nil
            }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !modifiers.isEmpty,
                  let letter = event.charactersIgnoringModifiers?.uppercased(), !letter.isEmpty else {
                return nil
            }
            onRecord(KeyBinding(keyCode: event.keyCode, modifiers: modifiers.rawValue, key: letter))
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
