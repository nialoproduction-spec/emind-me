import AppKit
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
    var id = UUID()
}

/// Tells a popup it's time to go out dramatically (hovered or clicked).
@MainActor
final class PopupLife: ObservableObject {
    @Published var dying = false
}

/// A reminder's popup: the habit card's look (the panel's theme), a lively
/// face from the face kit, the title and a short quote, no buttons. Hover
/// over it (or click) and it dies dramatically: the face goes x_x, it says
/// its last words, shakes, and dissolves into bits.
struct NoticePillView: View {
    let content: NoticeContent
    @ObservedObject var life: PopupLife
    var onTap: () -> Void = {}
    /// Called when the dissolve has finished, to take the window away.
    var onDied: () -> Void = {}

    @ObservedObject private var themeStore = ThemeStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var face = Kaomoji.random([.happy, .happy, .love, .calm, .shocked].randomElement()!)
    @State private var lastWords: String?
    @State private var shake: Double = 0
    @State private var dissolve: CGFloat = 0
    @State private var bits = DissolveBit.burst(count: 46)

    var body: some View {
        let theme = themeStore.theme
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
        ZStack {
            VStack(spacing: 6) {
                LivelyKaomojiView(face: face, color: theme.text)
                    .frame(width: 128, height: 64)

                Text(content.title)
                    .font(theme.titleFont)
                    .foregroundStyle(theme.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)

                if let line = lastWords ?? content.detail {
                    Text(lastWords == nil ? "“\(line)”" : line)
                        .font(.system(size: max(theme.fontSize - 2, 10), weight: lastWords == nil ? .regular : .semibold)
                            .italic())
                        .foregroundStyle(theme.text.opacity(lastWords == nil ? 0.55 : 0.9))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(
                shape.fill(theme.background.opacity(theme.backgroundOpacity))
                    .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
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
        .onTapGesture { life.dying = true }
        .onChange(of: life.dying) {
            if life.dying { Task { await die() } }
        }
    }

    @MainActor private func die() async {
        guard lastWords == nil else { return }
        face = Kaomoji.random(.dead)
        lastWords = ReminderQuotes.lastWords.randomElement()
        if !reduceMotion {
            for angle in [-5.0, 4.5, -3.5, 3, -2, 0] {
                withAnimation(.easeInOut(duration: 0.07)) { shake = angle }
                try? await Task.sleep(for: .milliseconds(70))
            }
            try? await Task.sleep(for: .milliseconds(380))
            withAnimation(.easeIn(duration: 0.95)) { dissolve = 1 }
            try? await Task.sleep(for: .milliseconds(1000))
        } else {
            try? await Task.sleep(for: .milliseconds(700))
        }
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
    static let size = CGSize(width: ReminderPanelController.liveReminderSize.width, height: 150)

    private var panel: ReminderPanel?
    private var hosting: NSHostingView<AnyView>?
    private var hideTask: Task<Void, Never>?
    private var hoverTask: Task<Void, Never>?
    private var generation = 0
    private var life = PopupLife()

    private init() {}

    func show(_ content: NoticeContent) {
        let panel = ensurePanel()
        generation += 1
        hideTask?.cancel()
        let life = PopupLife()
        self.life = life
        let shownGeneration = generation
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

        if !content.sticky {
            let seconds = content.duration
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                self?.hide(ifGeneration: shownGeneration)
            }
        }
    }

    func hide() {
        hide(ifGeneration: nil)
    }

    /// Hovering over the popup kills it (dramatically). Only once the
    /// pointer has been outside it first, so a popup that appears right
    /// under the pointer isn't killed before it's read.
    private func watchForHover(life: PopupLife, generation shown: Int) {
        hoverTask?.cancel()
        hoverTask = Task { [weak self] in
            var wasOutside = false
            try? await Task.sleep(for: .milliseconds(600))
            while !Task.isCancelled {
                guard let self, self.generation == shown, let panel = self.panel, panel.isVisible else { return }
                let inside = panel.frame.contains(NSEvent.mouseLocation)
                if !inside { wasOutside = true }
                if inside, wasOutside, !life.dying {
                    life.dying = true
                    self.hideTask?.cancel() // it leaves by dying now
                    return
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
