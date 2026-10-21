import AppKit
import Combine
import SwiftUI

/// What one popup says. Everything is plain data so tests can check it
/// without any window.
struct NoticeContent: Equatable {
    var title: String
    /// Right-hand text ("Rest for 1 minute."), when there's no countdown.
    var detail: String? = nil
    /// Right-hand live countdown to this moment. It's drawn from the
    /// absolute date each second, so it can never drift (rule 3).
    var countdownTo: Date? = nil
    /// Counts up from this moment instead ("+3:12"): time away after a break.
    var countUpFrom: Date? = nil
    var face: Face? = nil
    /// The reminder's category ("Health"), shown as a coloured tag.
    var category: String? = nil
    /// Which colours the notch uses for it (work, break, away).
    var tone: IslandTone? = nil
    /// Stays on screen until replaced or hidden, instead of fading after
    /// `duration` seconds.
    var sticky = false
    var duration: TimeInterval = 6
    /// The countdown in plain seconds ("10", "9" … "0"), for the last ones.
    var secondsOnly = false
    /// The reminder it's for, so ignoring it (or not) can be counted.
    var itemID: UUID? = nil
    /// Ignored again and again: angry from the start, red edge, a buzz, and
    /// it stays until clicked.
    var loud = false
    /// The face's mood while it waits (a finished render is happy).
    var mood: FaceMood? = nil
    /// The detail is information (a file name, "Due in 3 days"), not a
    /// quote: no quote marks.
    var plainDetail = false
    var id = UUID()
}

/// How a popup goes out.
enum PopupExit: Equatable {
    /// Sent off (click, double-click or a rest of the pointer): it cries its
    /// last words, then "Sayonara.".
    case dismissed
    /// Its time ran out while you kept typing or moving the pointer: it gets
    /// angry, buzzes, huffs "Ignored again…", then "Sayonara.".
    case ignored
}

/// Tells a popup it's time to go out dramatically, and which way.
@MainActor
final class PopupLife: ObservableObject {
    @Published var exit: PopupExit?
}

/// A reminder's popup: the habit card's look (the panel's theme), the
/// original traced face, the title and a short quote, no buttons. Send it
/// off with a click (or a double-click, or by resting the pointer on it, as
/// chosen in Settings) and it goes dramatically: last words in tears with a
/// shake, then "Sayonara." at peace, then it dissolves into nothing. Ignore
/// it while you work and it leaves angry instead.
struct NoticePillView: View {
    /// Where it is in its life. Previews start it at a later stage.
    enum Stage: Equatable {
        case alive
        /// Its parting line: last words (sent off) or a huff (ignored).
        case parting(PopupExit, String)
        case sayonara(PopupExit)
    }

    let content: NoticeContent
    @ObservedObject var life: PopupLife
    var onTap: () -> Void = {}
    /// Called when the dissolve has finished, to take the window away.
    var onDied: () -> Void = {}

    @ObservedObject private var themeStore = ThemeStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage: Stage
    @ObservedObject private var popupSettings = AppSettings.reminderPopup
    @State private var shake: Double = 0
    @State private var dissolve: CGFloat = 0
    @State private var bits = DissolveBit.burst(count: 46)

    init(content: NoticeContent, life: PopupLife, stage: Stage = .alive,
         onTap: @escaping () -> Void = {}, onDied: @escaping () -> Void = {}) {
        self.content = content
        _life = ObservedObject(wrappedValue: life)
        self.onTap = onTap
        self.onDied = onDied
        _stage = State(initialValue: stage)
    }

    /// The original faces' moods: cute while it waits (angry when it's
    /// loud), crying when sent off, at peace for "Sayonara.", angry all the
    /// way out when ignored.
    static func mood(for stage: Stage, loud: Bool = false, waiting: FaceMood? = nil) -> FaceMood {
        switch stage {
        case .alive: return loud ? .urgent : (waiting ?? .gentle)
        case .parting(.dismissed, _): return .skipped
        case .sayonara(.dismissed): return .snoozed
        case .parting(.ignored, _), .sayonara(.ignored): return .urgent
        }
    }

    private var line: String? {
        switch stage {
        case .alive: return content.detail
        case .parting(_, let words): return words
        case .sayonara: return "Sayonara."
        }
    }

    private var ignored: Bool {
        switch stage {
        case .parting(.ignored, _), .sayonara(.ignored): return true
        default: return false
        }
    }

    var body: some View {
        let theme = themeStore.theme
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
        let quiet = stage == .alive && !content.loud
        let angry = ignored || content.loud
        ZStack {
            VStack(spacing: 6) {
                AnimatedFaceView(mood: Self.mood(for: stage, loud: content.loud, waiting: content.mood), color: theme.text)

                Text(content.title)
                    .font(theme.titleFont)
                    .foregroundStyle(theme.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)

                if let line {
                    Text(quiet && !content.plainDetail ? "“\(line)”" : line)
                        .font(.system(size: max(theme.fontSize - 2, 10), weight: quiet ? .regular : .semibold)
                            .italic())
                        .foregroundStyle(theme.text.opacity(quiet ? 0.55 : 0.9))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .id(line)
                        .transition(.opacity)
                }

            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(
                shape.fill(theme.background.opacity(theme.backgroundOpacity))
                    .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    // Ignored: an angry red edge.
                    .overlay(shape.strokeBorder(Color.red.opacity(angry ? 0.75 : 0), lineWidth: content.loud ? 3 : 2))
                    .animation(.easeOut(duration: 0.2), value: angry)
            )
            .clipShape(shape)
            .rotationEffect(.degrees(shake))
            .scaleEffect(1 - 0.12 * dissolve)
            .blur(radius: 8 * dissolve)
            .opacity(Double(max(0, 1 - dissolve * 1.8)))

            // The bits it falls apart into.
            DissolveField(bits: bits, progress: dissolve,
                          colors: [theme.text, theme.text.opacity(0.6), theme.accent, theme.background])
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: popupSettings.value.dismiss == .doubleClick ? 2 : 1) {
            if popupSettings.value.dismiss != .hover, life.exit == nil { life.exit = .dismissed }
        }
        .onChange(of: life.exit) {
            if let exit = life.exit { Task { await die(exit) } }
        }
    }

    /// Its parting line (long enough to read): crying last words with a
    /// shake when sent off, an angry huff when ignored (the controller buzzes
    /// the window and the trackpad meanwhile). Then "Sayonara.", then it
    /// dissolves into nothing.
    @MainActor private func die(_ exit: PopupExit) async {
        guard stage == .alive else { return }
        let lines = exit == .ignored ? ReminderQuotes.ignoredWords : ReminderQuotes.lastWords
        withAnimation(.easeOut(duration: 0.2)) { stage = .parting(exit, lines.randomElement() ?? "Fine.") }
        guard !reduceMotion else {
            try? await Task.sleep(for: .milliseconds(2400))
            onDied()
            return
        }
        if exit == .dismissed {
            for angle in [-6.0, 5.5, -4.5, 4, -3, 2, -1, 0] {
                withAnimation(.easeInOut(duration: 0.06)) { shake = angle }
                try? await Task.sleep(for: .milliseconds(60))
            }
            try? await Task.sleep(for: .milliseconds(2000)) // time to read it
        } else {
            try? await Task.sleep(for: .milliseconds(2600)) // buzzing, then a glare
        }

        withAnimation(.easeInOut(duration: 0.35)) { stage = .sayonara(exit) }
        try? await Task.sleep(for: .milliseconds(1500))

        withAnimation(.easeIn(duration: 1.1)) { dissolve = 1 }
        try? await Task.sleep(for: .milliseconds(1150))
        onDied()
    }
}

/// One fleck of a dissolving popup: where it starts (0…1 across the card),
/// which way it flies, how big it is and which colour.
struct DissolveBit: Identifiable {
    let id: Int
    let start: CGPoint
    let drift: CGSize
    let size: CGFloat
    let colorIndex: Int

    static func burst(count: Int) -> [DissolveBit] {
        (0..<count).map { i in
            let start = CGPoint(x: .random(in: 0.05...0.95), y: .random(in: 0.08...0.92))
            // Mostly up and outward, like ash in a draught.
            let drift = CGSize(width: (start.x - 0.5) * .random(in: 60...160) + .random(in: -20...20),
                               height: -.random(in: 30...120))
            return DissolveBit(id: i, start: start, drift: drift, size: .random(in: 2...6),
                               colorIndex: Int.random(in: 0..<4))
        }
    }
}

struct DissolveField: View {
    let bits: [DissolveBit]
    let progress: CGFloat
    let colors: [Color]

    var body: some View {
        GeometryReader { geo in
            ForEach(bits) { bit in
                RoundedRectangle(cornerRadius: 1.2)
                    .fill(colors[bit.colorIndex % colors.count])
                    .frame(width: bit.size, height: bit.size)
                    .rotationEffect(.degrees(Double(progress) * 220 * (bit.id.isMultiple(of: 2) ? 1 : -1)))
                    .position(x: bit.start.x * geo.size.width + bit.drift.width * progress,
                              y: bit.start.y * geo.size.height + bit.drift.height * progress)
                    // Appear as the card goes, then fade out as they drift.
                    .opacity(Double(min(1, progress * 5) * (1 - progress)))
            }
        }
    }
}

/// Reminders' popup (the break timer has its own, at the notch: see
/// BreakIsland.swift). Shows in its own small non-activating window under the menu
/// bar, over full-screen apps too. One at a time: a new one replaces the one
/// showing. Click it to put it away.
@MainActor
final class NoticePillController {
    static let shared = NoticePillController()

    /// The habit card's width; shorter, with no buttons.
    static let size = CGSize(width: ReminderPanelController.liveReminderSize.width, height: 164)

    private var panel: ReminderPanel?
    private var hosting: NSHostingView<AnyView>?
    private var hideTask: Task<Void, Never>?
    private var hoverTask: Task<Void, Never>?
    private var generation = 0
    private var life = PopupLife()
    private var exitWatch: AnyCancellable?

    /// A reminder's popup went: ignored (true) or sent off (false). Faded
    /// while you were away isn't reported. Set by the scheduler.
    var onOutcome: ((UUID, Bool) -> Void)?

    private init() {}

    func show(_ content: NoticeContent) {
        let panel = ensurePanel()
        generation += 1
        hideTask?.cancel()
        let life = PopupLife()
        self.life = life
        let shownGeneration = generation
        exitWatch = nil
        if let itemID = content.itemID {
            exitWatch = life.$exit.compactMap { $0 }.first().sink { [weak self] exit in
                self?.onOutcome?(itemID, exit == .ignored)
            }
        }
        hosting?.rootView = AnyView(
            NoticePillView(content: content, life: life,
                           onDied: { [weak self] in self?.vanish(ifGeneration: shownGeneration) })
                .id(content.id)
        )
        let target = targetFrame(size: Self.size)
        if !panel.isVisible {
            // Slides down a little as it fades in, like a notification.
            panel.alphaValue = 0
            panel.setFrame(target.offsetBy(dx: 0, dy: 10), display: true)
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(target, display: true)
                panel.animator().alphaValue = 1
            }
        } else {
            panel.setFrame(target, display: true)
            fade(to: 1, duration: 0.18)
        }

        watchForHover(life: life, generation: shownGeneration)
        if content.loud {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(350)) // after it has slid in
                await self?.buzz(generation: shownGeneration)
            }
        }

        if !content.sticky {
            let seconds = content.duration
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, let self else { return }
                self.timeUp(life: life, generation: shownGeneration)
            }
        }
    }

    /// Any keyboard, mouse or trackpad use this recently counts as busy.
    nonisolated static let busyWithin: TimeInterval = 3

    /// Its time ran out: ignored if you were typing or moving the pointer
    /// just now (and the pointer isn't resting on it, reading it). Away or
    /// idle, it just fades.
    nonisolated static func wasIgnored(idleSeconds: TimeInterval, pointerOnIt: Bool) -> Bool {
        !pointerOnIt && idleSeconds < busyWithin
    }

    private func timeUp(life: PopupLife, generation shown: Int) {
        guard shown == generation, let panel, panel.isVisible, life.exit == nil else { return }
        let ignored = Self.wasIgnored(idleSeconds: AwayDetector.idleSeconds(),
                                      pointerOnIt: panel.frame.contains(NSEvent.mouseLocation))
        guard ignored else {
            hide(ifGeneration: shown)
            return
        }
        // It leaves angry; the view calls onDied when it has dissolved.
        life.exit = .ignored
        Task { [weak self] in await self?.buzz(generation: shown) }
    }

    /// The window's side-to-side jolts, in points, for one burst.
    static let buzzOffsets: [CGFloat] = [-9, 9, -8, 8, -7, 7, -6, 6, -4, 4, -3, 3, -1.5, 1.5, 0]

    /// The "vibration" when it's ignored: two bursts of the whole window
    /// buzzing side to side, with trackpad taps along (macOS only plays
    /// those while a finger is on the trackpad). Reduce Motion: taps only.
    private func buzz(generation shown: Int) async {
        guard let panel else { return }
        let home = panel.frame.origin
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        try? await Task.sleep(for: .milliseconds(250)) // the face turns angry first
        for _ in 0..<2 {
            for (step, dx) in Self.buzzOffsets.enumerated() {
                guard generation == shown, panel.isVisible else { return }
                if !still { panel.setFrameOrigin(NSPoint(x: home.x + dx, y: home.y)) }
                if step % 3 == 0 {
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                }
                try? await Task.sleep(for: .milliseconds(28))
            }
            guard generation == shown else { return }
            panel.setFrameOrigin(home)
            try? await Task.sleep(for: .milliseconds(260))
        }
    }

    func hide() {
        hide(ifGeneration: nil)
    }

    /// How long the pointer has to rest on it to send it off (when that's
    /// the chosen way): long enough that passing over it doesn't count.
    static let hoverDwell: TimeInterval = 0.9

    /// Once it's going (×, double-click or a rest of the pointer), the timed
    /// fade is off: it leaves by its dramatic exit. Resting the pointer only
    /// counts if it was outside first, so a popup that appears right under
    /// the pointer isn't sent off before it's read.
    private func watchForHover(life: PopupLife, generation shown: Int) {
        hoverTask?.cancel()
        hoverTask = Task { [weak self] in
            var wasOutside = false
            var restingSince: Date?
            try? await Task.sleep(for: .milliseconds(400))
            while !Task.isCancelled {
                guard let self, self.generation == shown, let panel = self.panel, panel.isVisible else { return }
                if life.exit != nil {
                    self.hideTask?.cancel()
                    return
                }
                if AppSettings.reminderPopup.value.dismiss == .hover {
                    let inside = panel.frame.contains(NSEvent.mouseLocation)
                    if !inside { wasOutside = true; restingSince = nil }
                    if inside, wasOutside {
                        let since = restingSince ?? Date()
                        restingSince = since
                        if Date().timeIntervalSince(since) >= Self.hoverDwell { life.exit = .dismissed }
                    }
                }
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    /// After the dissolve: gone at once (it already faded itself).
    private func vanish(ifGeneration expected: Int) {
        guard let panel, expected == generation else { return }
        hoverTask?.cancel()
        hideTask?.cancel()
        generation += 1
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    private func hide(ifGeneration expected: Int?) {
        guard let panel, panel.isVisible else { return }
        if let expected, expected != generation { return } // replaced by a newer popup
        hideTask?.cancel()
        hoverTask?.cancel()
        generation += 1
        let mine = generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == mine else { return } // shown again mid-fade
                self.panel?.orderOut(nil)
                self.panel?.alphaValue = 1
            }
        })
    }

    private func ensurePanel() -> ReminderPanel {
        if let panel { return panel }
        let rect = NSRect(origin: .zero, size: Self.size)
        let newPanel = ReminderPanel(contentRect: rect)
        newPanel.isMovableByWindowBackground = false // a click puts it away; no dragging
        newPanel.hasShadow = true
        let view = NSHostingView(rootView: AnyView(EmptyView()))
        view.frame = rect
        view.autoresizingMask = [.width, .height]
        newPanel.contentView = view
        panel = newPanel
        hosting = view
        return newPanel
    }

    private func fade(to alpha: CGFloat, duration: TimeInterval) {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = alpha
        }
    }

    /// Where the panel's own pill would appear (your placement setting, top
    /// right by default). If the panel is open there, just below it instead,
    /// so the popup never covers the list.
    private func targetFrame(size: CGSize) -> NSRect {
        let panelController = ReminderPanelController.shared
        var frame = panelController.frameForNotice(size: size)
        if let open = panelController.visibleFrameOnScreen, open.intersects(frame) {
            let screen = NSScreen.screens.first { $0.frame.intersects(open) } ?? NSScreen.main
            let visible = screen?.visibleFrame ?? .zero
            let below = open.minY - size.height - 8
            frame.origin.y = below >= visible.minY ? below : min(open.maxY + 8, visible.maxY - size.height)
            frame.origin.x = min(max(open.maxX - size.width, visible.minX + 8), visible.maxX - size.width - 8)
        }
        return frame
    }
}
