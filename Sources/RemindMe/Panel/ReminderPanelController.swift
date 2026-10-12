import AppKit
import SwiftUI
import SwiftData

/// Owns the floating panel: creation, SwiftUI hosting, position persistence,
/// and the animated collapse/expand resize. One instance for the app's
/// lifetime; the panel itself is just shown/hidden/resized, never recreated,
/// so dragged position and expand state survive toggling.
@MainActor
final class ReminderPanelController {
    static let shared = ReminderPanelController()

    private(set) var panel: ReminderPanel!
    private var hostingView: NSHostingView<AnyView>!
    private(set) var isExpanded = false

    private static let collapsedSize = CGSize(width: 220, height: 56)
    private static let expandedSize = CGSize(width: 320, height: 420)
    private static let liveReminderSize = CGSize(width: 280, height: 230)
    private static let originDefaultsKey = "panel.origin.v1"

    /// Whether the panel was already visible/expanded before something
    /// force-presented itself (a live reminder, the end-of-day summary), so
    /// dismissing it can put things back the way they were rather than
    /// always snapping to collapsed.
    private var stateBeforeOverlay: (wasVisible: Bool, wasExpanded: Bool)?

    private init() {}

    /// Builds the panel the first time it's needed. Call once, after the
    /// SwiftData container exists.
    func configure(modelContainer: ModelContainer) {
        guard panel == nil else { return }

        let origin = Self.restoredOrigin() ?? Self.defaultOrigin(for: Self.collapsedSize)
        let rect = NSRect(origin: origin, size: Self.collapsedSize)

        let newPanel = ReminderPanel(contentRect: rect)
        let content = AnyView(
            PanelRootView(controller: self)
                .modelContainer(modelContainer)
        )
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(origin: .zero, size: Self.collapsedSize)
        newPanel.contentView = hosting

        panel = newPanel
        hostingView = hosting

        // Persist wherever the user drags it.
        NotificationCenter.default.addObserver(
            self, selector: #selector(panelDidMove),
            name: NSWindow.didMoveNotification, object: newPanel
        )
    }

    func show() {
        guard let panel else { return }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggleVisibility() {
        guard let panel else { return }
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Animates between the collapsed pill and the expanded reminder list,
    /// keeping the top-left corner anchored so growth never jumps the panel
    /// to an unexpected part of the screen.
    func setExpanded(_ expanded: Bool, animated: Bool = true) {
        guard let panel, isExpanded != expanded else { return }
        isExpanded = expanded

        let size = expanded ? Self.expandedSize : Self.collapsedSize
        let currentFrame = panel.frame
        let newOrigin = NSPoint(
            x: currentFrame.minX,
            y: currentFrame.maxY - size.height
        )
        var newFrame = NSRect(origin: newOrigin, size: size)
        newFrame = Self.clampedToVisibleScreen(newFrame)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(newFrame, display: true)
            }
        } else {
            panel.setFrame(newFrame, display: true)
        }
    }

    func toggleExpanded() { setExpanded(!isExpanded) }

    // MARK: - Forced overlays (live reminder, end-of-day summary)

    /// Pops the panel open to the live-reminder size regardless of its
    /// current state, remembering that state so `dismissLiveReminder` can
    /// restore it. The SwiftUI layer decides what's actually drawn (watching
    /// `ReminderScheduler.activeOccurrence`); this just handles geometry.
    func presentLiveReminder() {
        rememberStateBeforeOverlay()
        show()
        resize(to: Self.liveReminderSize, animated: true)
    }

    func dismissLiveReminder() {
        restoreStateAfterOverlay()
    }

    /// Same idea, sized for the end-of-day summary (reuses the expanded size).
    func presentOverlay() {
        rememberStateBeforeOverlay()
        show()
        isExpanded = true
        resize(to: Self.expandedSize, animated: true)
    }

    func dismissOverlay() {
        restoreStateAfterOverlay()
    }

    private func rememberStateBeforeOverlay() {
        guard stateBeforeOverlay == nil else { return } // already mid-overlay; don't overwrite
        stateBeforeOverlay = (isVisible, isExpanded)
    }

    private func restoreStateAfterOverlay() {
        let previous = stateBeforeOverlay ?? (false, false)
        stateBeforeOverlay = nil

        if !previous.wasVisible {
            hide()
            isExpanded = false
            resize(to: Self.collapsedSize, animated: false)
        } else {
            isExpanded = previous.wasExpanded
            resize(to: previous.wasExpanded ? Self.expandedSize : Self.collapsedSize, animated: true)
        }
    }

    private func resize(to size: CGSize, animated: Bool) {
        guard let panel else { return }
        let currentFrame = panel.frame
        let newOrigin = NSPoint(x: currentFrame.minX, y: currentFrame.maxY - size.height)
        let newFrame = Self.clampedToVisibleScreen(NSRect(origin: newOrigin, size: size))

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(newFrame, display: true)
            }
        } else {
            panel.setFrame(newFrame, display: true)
        }
    }

    // MARK: - Position persistence

    @objc private func panelDidMove() {
        guard let panel else { return }
        let point = panel.frame.origin
        UserDefaults.standard.set(["x": point.x, "y": point.y], forKey: Self.originDefaultsKey)
    }

    private static func restoredOrigin() -> NSPoint? {
        guard let dict = UserDefaults.standard.dictionary(forKey: originDefaultsKey),
              let x = dict["x"] as? Double, let y = dict["y"] as? Double else { return nil }
        return NSPoint(x: x, y: y)
    }

    private static func defaultOrigin(for size: CGSize) -> NSPoint {
        guard let screen = NSScreen.main?.visibleFrame else { return .zero }
        // Top-right-ish, out of the way of most menu bar items.
        return NSPoint(x: screen.maxX - size.width - 24, y: screen.maxY - size.height - 12)
    }

    private static func clampedToVisibleScreen(_ frame: NSRect) -> NSRect {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame else { return frame }
        var result = frame
        result.origin.x = min(max(result.origin.x, screen.minX), screen.maxX - result.width)
        result.origin.y = min(max(result.origin.y, screen.minY), screen.maxY - result.height)
        return result
    }
}
