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

/// The reminder popup, macOS-notification style: frosted glass, a blue
/// app-icon tile with a bell that rings as it arrives, the title in bold with
/// "now" on the right, the schedule and category underneath, and a thin line
/// along the bottom that runs down until it goes away.
struct NoticePillView: View {
    let content: NoticeContent
    var onTap: () -> Void = {}

    @State private var bellAngle: Double = 0
    @State private var remaining: CGFloat = 1

    static let titleFont = NSFont.systemFont(ofSize: 14, weight: .semibold)
    static let lineFont = NSFont.systemFont(ofSize: 12)

    var body: some View {
        HStack(spacing: 12) {
            iconTile
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(content.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer(minLength: 4)
                    Text("now")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
                HStack(spacing: 6) {
                    if let detail = content.detail {
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    if let category = content.category {
                        HStack(spacing: 4) {
                            Circle().fill(CategoryStyle.color(for: category)).frame(width: 6, height: 6)
                            Text(category)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(CategoryStyle.color(for: category))
                        }
                    }
                }
            }
            .lineLimit(1)
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                FrostedGlass()
                Color.black.opacity(0.12)
            }
        )
        .overlay(alignment: .bottom) {
            if !content.sticky {
                GeometryReader { geo in
                    Capsule()
                        .fill(Color.white.opacity(0.28))
                        .frame(width: geo.size.width * remaining, height: 2)
                }
                .frame(height: 2)
                .padding(.horizontal, 16)
                .padding(.bottom, 5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onAppear {
            guard !content.sticky else { return }
            withAnimation(.linear(duration: content.duration)) { remaining = 0 }
        }
        .task {
            // A little ring as it arrives.
            for angle in [16.0, -13, 9, -5, 0] {
                withAnimation(.easeInOut(duration: 0.11)) { bellAngle = angle }
                try? await Task.sleep(for: .milliseconds(110))
            }
        }
    }

    private var iconTile: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(LinearGradient(
                colors: [Color(red: 0.36, green: 0.64, blue: 1.0), Color(red: 0.16, green: 0.42, blue: 0.96)],
                startPoint: .top, endPoint: .bottom
            ))
            .frame(width: 36, height: 36)
            .overlay(
                Image(systemName: "bell.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(bellAngle), anchor: .top)
            )
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}

/// The blurred, see-through backdrop macOS uses for notifications and HUDs.
struct FrostedGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Reminders' popup (the break timer has its own, at the notch: see
/// BreakIsland.swift). Shows in its own small non-activating window under the menu
/// bar, over full-screen apps too. One at a time: a new one replaces the one
/// showing. Click it to put it away.
@MainActor
final class NoticePillController {
    static let shared = NoticePillController()

    static let height: CGFloat = 64

    /// As wide as the text needs, like a macOS notification: 280–360 pt.
    static func width(for content: NoticeContent) -> CGFloat {
        func width(_ text: String, _ font: NSFont) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: font]).width)
        }
        let top = width(content.title, NoticePillView.titleFont) + 8 + 24 // + "now"
        var bottom = width(content.detail ?? "", NoticePillView.lineFont)
        if let category = content.category {
            bottom += 6 + 10 + width(category, .systemFont(ofSize: 11, weight: .medium))
        }
        return min(360, max(280, 12 + 36 + 12 + max(top, bottom) + 14))
    }

    private var panel: ReminderPanel?
    private var hosting: NSHostingView<AnyView>?
    private var hideTask: Task<Void, Never>?
    private var generation = 0

    private init() {}

    func show(_ content: NoticeContent) {
        let panel = ensurePanel()
        generation += 1
        hideTask?.cancel()
        hosting?.rootView = AnyView(
            NoticePillView(content: content, onTap: { [weak self] in self?.hide() }).id(content.id)
        )
        let target = targetFrame(size: CGSize(width: Self.width(for: content), height: Self.height))
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

        if !content.sticky {
            let seconds = content.duration
            let shownGeneration = generation
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

    private func hide(ifGeneration expected: Int?) {
        guard let panel, panel.isVisible else { return }
        if let expected, expected != generation { return } // replaced by a newer popup
        hideTask?.cancel()
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
        let rect = NSRect(x: 0, y: 0, width: 220, height: Self.height)
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
