import AppKit
import SwiftUI
import SwiftData

/// When the floating panel tucks itself away. It behaves like a notification:
/// it appears when needed, stays a few seconds, and fades out on its own.
enum PanelAutoHide {
    /// How long the time / next-reminder pill stays up after appearing.
    static let peekDuration: TimeInterval = 6
    /// After the pointer leaves the pill, how long before it goes.
    static let hoverGrace: TimeInterval = 2
    /// The expanded list goes after this long with no pointer or typing.
    static let expandedIdle: TimeInterval = 15
    static let fadeIn: TimeInterval = 0.18
    static let fadeOut: TimeInterval = 0.3

    /// `shownAt`: when the pill (re)appeared. `lastEngaged`: the last moment
    /// the pointer was over the panel, the user typed, or something pinned it.
    static func shouldHide(now: Date, shownAt: Date, lastEngaged: Date, isExpanded: Bool) -> Bool {
        if isExpanded {
            return now.timeIntervalSince(lastEngaged) >= expandedIdle
        }
        return now.timeIntervalSince(shownAt) >= peekDuration
            && now.timeIntervalSince(lastEngaged) >= hoverGrace
    }
}

/// Owns the floating panel: creation, SwiftUI hosting, position persistence,
/// the animated collapse/expand resize, and when it fades in and out. One
/// instance for the app's lifetime; the panel itself is just shown, hidden
/// and resized, never recreated, so its dragged position survives.
///
/// Visibility follows `PanelAutoHide`: the pill appears on a menu bar click
/// and fades out by itself; the expanded list stays while it's being used
/// and fades out on a click elsewhere or after a quiet spell; a live reminder
/// or the end-of-day summary fades away when it's done instead of leaving
/// the pill stuck on screen. None of this touches reminder timing — the
/// scheduler still decides when reminders appear and how long they stay.
@MainActor
final class ReminderPanelController: ObservableObject {
    static let shared = ReminderPanelController()

    private(set) var panel: ReminderPanel!
    private var hostingView: NSHostingView<AnyView>!
    @Published private(set) var isExpanded = false
    /// True while the panel is fading out. The SwiftUI layer keeps drawing
    /// whatever it was showing until the fade finishes, so nothing swaps
    /// mid-fade.
    @Published private(set) var isHiding = false

    // Auto-hide bookkeeping.
    private var shownAt = Date.distantPast
    private var lastEngaged = Date.distantPast
    private var idleWatch: Task<Void, Never>?
    private var outsideClickMonitor: Any?
    /// Bumped on every show/hide so a fade-out that's been overtaken by a new
    /// show doesn't take the panel off screen when it completes.
    private var visibilityGeneration = 0

    private static let collapsedSize = CGSize(width: 220, height: 56)
    private static let expandedSize = CGSize(width: 320, height: 420)
    /// Face window + up to two lines of title + buttons.
    static let liveReminderSize = CGSize(width: 280, height: 204)
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

    var isVisible: Bool { panel?.isVisible ?? false }
    /// On screen and not on its way out.
    private var isOnScreen: Bool { isVisible && !isHiding }

    /// Brings the panel up (fading in if it was hidden) without taking focus
    /// from the app being used, and starts the auto-hide watch.
    func show() {
        guard let panel else { return }
        visibilityGeneration += 1 // overtakes any fade-out in progress
        let now = Date()
        if !isOnScreen {
            shownAt = now
            if !panel.isVisible { panel.alphaValue = 0 }
            panel.orderFrontRegardless()
        }
        isHiding = false
        lastEngaged = now
        fade(to: 1, duration: PanelAutoHide.fadeIn)
        startWatching()
    }

    /// Fades the panel out, then takes it off screen and resets it to the
    /// pill for next time.
    func hide() {
        guard let panel, isOnScreen else { return }
        isHiding = true
        stopWatching()
        visibilityGeneration += 1
        let generation = visibilityGeneration
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = PanelAutoHide.fadeOut
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in self?.finishHide(generation: generation) }
        })
    }

    private func finishHide(generation: Int) {
        guard let panel, generation == visibilityGeneration else { return } // shown again mid-fade
        panel.orderOut(nil)
        panel.alphaValue = 1
        isHiding = false
        // Hidden in the middle of a live reminder (menu bar click): keep its
        // size so it comes back intact. Otherwise start fresh as the pill.
        guard !isOverlayActive else { return }
        isExpanded = false
        resize(to: Self.collapsedSize, animated: false)
    }

    /// Menu bar click: show the pill (it then hides itself), or put the
    /// panel away if it's already up.
    func toggleVisibility() {
        guard panel != nil else { return }
        if isOnScreen { hide() } else { show() }
    }

    /// Typing in the panel counts as using it, even with the pointer elsewhere.
    func noteActivity() {
        lastEngaged = Date()
    }

    private func fade(to alpha: CGFloat, duration: TimeInterval) {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = alpha
        }
    }

    // MARK: - Auto-hide watch (only runs while the panel is on screen)

    private func startWatching() {
        if idleWatch == nil {
            idleWatch = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard let self, !Task.isCancelled else { return }
                    self.checkIdle()
                }
            }
        }
        if outsideClickMonitor == nil {
            // Global monitors only see clicks in *other* apps, so clicks on the
            // panel, its settings sheet or the menu bar icon never trigger this.
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] _ in
                Task { @MainActor in self?.handleClickElsewhere() }
            }
        }
    }

    private func stopWatching() {
        idleWatch?.cancel()
        idleWatch = nil
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    /// Things that keep the panel up however long it's been: a live reminder
    /// or end-of-day summary (the scheduler controls those), the settings
    /// sheet, or the pointer resting on the panel.
    private var isPinned: Bool {
        guard let panel else { return false }
        return isOverlayActive
            || panel.attachedSheet != nil
            || panel.frame.contains(NSEvent.mouseLocation)
    }

    private func checkIdle() {
        guard isOnScreen else { return }
        let now = Date()
        if isPinned {
            lastEngaged = now
            return
        }
        if PanelAutoHide.shouldHide(now: now, shownAt: shownAt, lastEngaged: lastEngaged, isExpanded: isExpanded) {
            hide()
        }
    }

    private func handleClickElsewhere() {
        guard isOnScreen, !isOverlayActive, panel?.attachedSheet == nil else { return }
        hide()
    }

    /// Animates between the collapsed pill and the expanded reminder list,
    /// keeping the top-left corner anchored so growth never jumps the panel
    /// to an unexpected part of the screen.
    func setExpanded(_ expanded: Bool, animated: Bool = true) {
        guard let panel, isExpanded != expanded else { return }
        isExpanded = expanded
        let now = Date()
        lastEngaged = now
        if !expanded { shownAt = now } // collapsed back to the pill: it peeks, then goes

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
        presentForced(size: Self.liveReminderSize)
    }

    func dismissLiveReminder() {
        restoreStateAfterOverlay()
    }

    /// Same idea, sized for the end-of-day summary (reuses the expanded size).
    func presentOverlay() {
        presentForced(size: Self.expandedSize, expanded: true)
    }

    func dismissOverlay() {
        restoreStateAfterOverlay()
    }

    private var isOverlayActive: Bool { stateBeforeOverlay != nil }

    private func presentForced(size: CGSize, expanded: Bool = false) {
        let wasHidden = !isOnScreen
        rememberStateBeforeOverlay()
        if expanded { isExpanded = true }
        if wasHidden {
            // Appear already at full size and fade in, rather than growing
            // from the pill while fading.
            resize(to: size, animated: false)
            show()
        } else {
            show()
            resize(to: size, animated: true)
        }
    }

    private func rememberStateBeforeOverlay() {
        guard stateBeforeOverlay == nil else { return } // already mid-overlay; don't overwrite
        stateBeforeOverlay = (isOnScreen, isExpanded)
    }

    private func restoreStateAfterOverlay() {
        let previous = stateBeforeOverlay ?? (false, false)
        stateBeforeOverlay = nil

        if previous.wasVisible && previous.wasExpanded && isOnScreen {
            // The list was open and in use when the reminder interrupted:
            // put it back, and let the normal idle rules take it from there.
            isExpanded = true
            lastEngaged = Date()
            resize(to: Self.expandedSize, animated: true)
        } else if isOnScreen {
            // It was only ever a notification: fade away rather than leave
            // the pill stuck on screen.
            hide()
        } else if !isHiding {
            // Already put away mid-reminder (menu bar click): just reset so
            // the next appearance is the pill again.
            isExpanded = false
            resize(to: Self.collapsedSize, animated: false)
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
