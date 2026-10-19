import AppKit
import SwiftUI
import SwiftData
import Combine

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
/// and fades out on a click elsewhere, after a quiet spell, or right after a
/// new reminder is added. A live reminder stays until it's answered, then
/// fades away instead of leaving the pill stuck on screen.
///
/// Position follows `PlacementStore` (a corner, a dragged custom spot, or
/// under the menu bar icon); dragging the panel saves a custom spot.
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
    /// Set right after adding something: the panel doesn't auto-hide until
    /// the next click elsewhere.
    private var heldUntilClick = false
    /// Bumped on every show/hide so a fade-out that's been overtaken by a new
    /// show doesn't take the panel off screen when it completes.
    private var visibilityGeneration = 0

    /// The menu bar icon's frame on screen, for "under the menu bar icon"
    /// placement. Supplied by the app delegate.
    var statusItemFrame: (() -> CGRect?)?
    private var placementObserver: AnyCancellable?

    private static let collapsedSize = CGSize(width: 220, height: 56)
    static let expandedSize = CGSize(width: 340, height: 480)
    /// Face window + up to two lines of title + buttons + shortcut hint.
    static let liveReminderSize = CGSize(width: 280, height: 222)

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

        let rect = NSRect(origin: .zero, size: Self.collapsedSize)

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

        // Dragging the panel saves that spot as the custom placement.
        NotificationCenter.default.addObserver(
            self, selector: #selector(panelDidMove),
            name: NSWindow.didMoveNotification, object: newPanel
        )

        // Placement changed in Settings: move there right away if it's up.
        placementObserver = PlacementStore.shared.$settings
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, let panel = self.panel, self.isOnScreen, !Self.isUserDragging else { return }
                self.resize(to: panel.frame.size, animated: true)
            }
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
            if !panel.isVisible {
                panel.alphaValue = 0
                // Appear at the chosen placement (the screen or the menu bar
                // icon may have moved since last time).
                panel.setFrame(targetFrame(for: panel.frame.size), display: false)
            }
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
        heldUntilClick = false
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

    /// Menu bar click: open the main page (the list), or put the panel away
    /// if it's already up. A reminder waiting for an answer is never put away
    /// this way — the click brings it to the front instead.
    func toggleVisibility() {
        guard panel != nil else { return }
        if isOverlayActive {
            show()
        } else if isOnScreen {
            if isExpanded { hide() } else { setExpanded(true) }
        } else {
            openMainPage()
        }
    }

    /// Straight to the list at full size, fading in (no pill first).
    func openMainPage() {
        guard panel != nil else { return }
        isExpanded = true
        if !isOnScreen { resize(to: Self.expandedSize, animated: false) }
        show()
        if isOnScreen { resize(to: Self.expandedSize, animated: true) }
    }

    /// Right after something is added: the panel stays up, however long it
    /// sits, until the person clicks somewhere else on the screen (so they can
    /// see it in the list, or add another one).
    func keepOpenUntilClickAway() {
        heldUntilClick = true
        lastEngaged = Date()
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
            || heldUntilClick
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
    /// keeping the chosen corner (or the spot under the menu bar icon)
    /// anchored so growth never jumps the panel somewhere unexpected.
    func setExpanded(_ expanded: Bool, animated: Bool = true) {
        guard let panel, isExpanded != expanded else { return }
        isExpanded = expanded
        let now = Date()
        lastEngaged = now
        if !expanded { shownAt = now } // collapsed back to the pill: it peeks, then goes

        let size = expanded ? Self.expandedSize : Self.collapsedSize
        let newFrame = targetFrame(for: size)

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

    /// A Focus / full-screen app started while a reminder waits: fade it out
    /// but keep everything as is, so `presentLiveReminder` brings it back.
    func suspendLiveReminder() {
        hide()
    }

    /// Same idea, sized for the end-of-day summary (reuses the expanded size).
    func presentOverlay() {
        // A reminder on screen goes first; the summary shows once it's answered.
        if ReminderScheduler.shared.activeOccurrence != nil {
            rememberStateBeforeOverlay()
            return
        }
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
        // Something else is still waiting behind the one just closed (say, the
        // weekly summary behind a reminder): show that instead of closing.
        let scheduler = ReminderScheduler.shared
        if scheduler.activeOccurrence != nil {
            if !scheduler.isLiveReminderSuspended {
                show()
                resize(to: Self.liveReminderSize, animated: true)
            }
            return
        }
        if scheduler.showEndOfDaySummary || scheduler.showWeeklySummary {
            isExpanded = true
            show()
            resize(to: Self.expandedSize, animated: true)
            return
        }

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
        let newFrame = targetFrame(for: size)

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

    // MARK: - Placement

    /// Where a popup of `size` goes: the same spot as the panel's pill.
    func frameForNotice(size: CGSize) -> NSRect {
        targetFrame(for: size)
    }

    /// The panel's frame while it's on screen, else nil.
    var visibleFrameOnScreen: NSRect? {
        isOnScreen ? panel?.frame : nil
    }

    /// Where a panel of `size` belongs right now, per the placement setting.
    private func targetFrame(for size: CGSize) -> NSRect {
        let settings = PlacementStore.shared.settings
        let iconFrame = statusItemFrame?()
        return PanelPlacementMath.frame(
            for: settings.placement,
            size: size,
            visibleFrame: Self.screenFrame(for: settings, iconFrame: iconFrame),
            customTopLeft: settings.customTopLeft,
            statusItemFrame: iconFrame
        )
    }

    /// The screen to place on: the one with the menu bar icon or the custom
    /// spot when that's the placement, otherwise the main screen.
    private static func screenFrame(for settings: PlacementSettings, iconFrame: CGRect?) -> CGRect {
        let screens = NSScreen.screens
        func screen(containing point: CGPoint) -> NSScreen? {
            screens.first { $0.frame.contains(point) }
        }
        var chosen: NSScreen?
        switch settings.placement {
        case .menuBar:
            chosen = iconFrame.flatMap { screen(containing: CGPoint(x: $0.midX, y: $0.midY)) }
        case .custom:
            chosen = settings.customTopLeft.flatMap { screen(containing: CGPoint(x: $0.x + 1, y: $0.y - 1)) }
        default:
            break
        }
        return (chosen ?? NSScreen.main ?? screens.first)?.visibleFrame ?? .zero
    }

    /// Only moves made by the user dragging (mouse button held) count.
    private static var isUserDragging: Bool { NSEvent.pressedMouseButtons & 1 == 1 }

    @objc private func panelDidMove() {
        guard let panel, Self.isUserDragging else { return }
        PlacementStore.shared.pinCustom(topLeft: CGPoint(x: panel.frame.minX, y: panel.frame.maxY))
    }
}
