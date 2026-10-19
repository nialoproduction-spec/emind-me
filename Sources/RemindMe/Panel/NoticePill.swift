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

/// The popup itself: a dark rounded pill with a face, the title on the left,
/// and a countdown or short note on the right. Deliberately no app icon.
struct NoticePillView: View {
    let content: NoticeContent
    var onTap: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            if let face = content.face {
                Image(nsImage: MenuBarFace.faceImage(face, span: MenuBarFace.span(of: [face]), offset: .zero))
                    .renderingMode(.template)
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 38, height: 20)
            }
            Text(content.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 12)
            if let detail = content.detail {
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
            if let end = content.countdownTo {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(BreakCycleState.clockString(end.timeIntervalSince(context.date)))
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(content.detail == nil ? 0.8 : 0.55))
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(width: NoticePillController.size.width, height: NoticePillController.size.height)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.07).opacity(0.97))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

/// Reminders' popup (the break timer has its own, at the notch: see
/// BreakIsland.swift). Shows in its own small non-activating window under the menu
/// bar, over full-screen apps too. One at a time: a new one replaces the one
/// showing. Click it to put it away.
@MainActor
final class NoticePillController {
    static let shared = NoticePillController()

    static let size = CGSize(width: 380, height: 46)

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
        panel.setFrame(targetFrame(), display: true)
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
        let rect = NSRect(origin: .zero, size: Self.size)
        let newPanel = ReminderPanel(contentRect: rect)
        newPanel.isMovableByWindowBackground = false // a click puts it away; no dragging
        newPanel.hasShadow = true
        let view = NSHostingView(rootView: AnyView(EmptyView()))
        view.frame = rect
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
    private func targetFrame() -> NSRect {
        let size = Self.size
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
