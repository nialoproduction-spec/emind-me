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
    var face: Face? = nil
    /// Stays on screen until replaced or hidden, instead of fading after
    /// `duration` seconds.
    var sticky = false
    var duration: TimeInterval = 6
    var id = UUID()
}

/// The reminder popup, in the style of a macOS notification: frosted
/// glass, a blue bell, the time in bold and "Drink water due now" under it.
struct NoticePillView: View {
    let content: NoticeContent
    var shownAt = Date()
    var onTap: () -> Void = {}

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    static func line(for content: NoticeContent) -> String {
        [content.title, content.detail].compactMap { $0 }.joined(separator: " ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 19, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color(red: 0.25, green: 0.56, blue: 1.0))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.timeFormatter.string(from: shownAt))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(Self.line(for: content))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.62))
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                FrostedGlass()
                Color.black.opacity(0.18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
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

    static let height: CGFloat = 56

    /// As wide as the text needs, like the panel's own pill: 220–340 pt.
    static func width(for content: NoticeContent) -> CGFloat {
        let text = NoticePillView.line(for: content) as NSString
        let textWidth = ceil(text.size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width)
        return min(340, max(220, 16 + 24 + 12 + textWidth + 20))
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
        hosting?.rootView = AnyView(NoticePillView(content: content, onTap: { [weak self] in self?.hide() }))
        panel.setFrame(targetFrame(size: CGSize(width: Self.width(for: content), height: Self.height)), display: true)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        fade(to: 1, duration: 0.18)

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
