import AppKit

/// The floating panel window itself.
///
/// Adapted from the window-configuration pattern used by Vorssaint's pinned
/// screenshot panels (github.com/vorssaint/vorssaint-utils, GPL-3.0-or-later):
/// a borderless, non-activating `NSPanel` that can become key (so its text
/// field can take typed input) without ever activating this app or stealing
/// focus from whatever app is frontmost. `isMovableByWindowBackground` gives
/// free dragging without any manual mouse tracking.
final class ReminderPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        level = .floating
        // Visible on every Space, including over full-screen apps, and not
        // listed in the Space-cycling / Mission Control app switcher.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }

    /// Can take keyboard focus (so the add-reminder field works) without the
    /// app itself activating — that's what keeps this from stealing focus.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func accessibilitySubrole() -> NSAccessibility.Subrole? { .unknown }

    override func cancelOperation(_ sender: Any?) {
        // Esc dismisses the key field/focus rather than closing the panel.
        makeFirstResponder(nil)
    }
}
