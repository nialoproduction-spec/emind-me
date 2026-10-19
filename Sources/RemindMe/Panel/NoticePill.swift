import AppKit
import SwiftUI

/// What one popup says. Everything is plain data so tests can check it
/// without any window.
struct NoticeContent: Equatable {
    /// Left of the notch ("Time for a break", "Work").
    var title: String
    /// Right of the notch ("Rest for 5 minutes.").
    var detail: String? = nil
    /// Right of the notch: a live countdown to this moment. It's drawn from
    /// the absolute date each second, so it can never drift (rule 3).
    var countdownTo: Date? = nil
    var face: Face? = nil
    /// Stays out until replaced or hidden, instead of tucking back into the
    /// notch after `duration` seconds.
    var sticky = false
    var duration: TimeInterval = 6
    var id = UUID()
}

// MARK: - Geometry

/// Where the island sits: centred on the camera notch, as tall as the notch,
/// with a wing either side for text. Pure maths, so it's tested.
enum IslandGeometry {
    /// Room for the text on each side of the notch.
    static let wingWidth: CGFloat = 190
    /// Screens without a notch: a small gap in the middle instead.
    static let noNotchGap: CGFloat = 16
    static let noNotchHeight: CGFloat = 32
    static let cornerRadius: CGFloat = 12

    struct Layout: Equatable {
        /// The window, in screen coordinates.
        var frame: CGRect
        /// The black bit in the middle the text keeps clear of.
        var middleWidth: CGFloat
        var hasNotch: Bool
    }

    static func layout(screenFrame: CGRect, notch: CGSize) -> Layout {
        let hasNotch = notch.width > 0 && notch.height > 0
        let middle = hasNotch ? notch.width : noNotchGap
        let height = hasNotch ? notch.height : noNotchHeight
        let width = middle + wingWidth * 2
        return Layout(
            frame: CGRect(x: screenFrame.midX - width / 2, y: screenFrame.maxY - height, width: width, height: height),
            middleWidth: middle,
            hasNotch: hasNotch
        )
    }
}

extension NSScreen {
    /// The camera notch's size, or zero on a screen without one.
    @MainActor var notchSize: CGSize {
        guard safeAreaInsets.top > 0,
              let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return .zero }
        return CGSize(width: max(0, frame.width - left.width - right.width), height: safeAreaInsets.top)
    }
}

// MARK: - View

@MainActor
final class IslandModel: ObservableObject {
    @Published var content: NoticeContent?
    /// Out of the notch (full width, text showing) vs tucked in.
    @Published var isOpen = false
    @Published var layout = IslandGeometry.layout(screenFrame: .zero, notch: .zero)
}

/// The popup: a black shape that grows out of the notch like Dynamic Island,
/// text on the left, a countdown or note on the right, the notch in between.
struct IslandView: View {
    @ObservedObject var model: IslandModel
    var onTap: () -> Void = {}

    var body: some View {
        let layout = model.layout
        let height = layout.frame.height
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: IslandGeometry.cornerRadius,
                bottomTrailingRadius: IslandGeometry.cornerRadius,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(Color.black)
            .frame(width: model.isOpen ? layout.frame.width : layout.middleWidth, height: height)
            .opacity(model.isOpen || layout.hasNotch ? 1 : 0)

            if let content = model.content {
                HStack(spacing: 0) {
                    leftWing(content)
                        .frame(width: IslandGeometry.wingWidth, alignment: .leading)
                    Color.clear.frame(width: layout.middleWidth)
                    rightWing(content)
                        .frame(width: IslandGeometry.wingWidth, alignment: .trailing)
                }
                .frame(height: height)
                .opacity(model.isOpen ? 1 : 0)
                .id(content.id)
                .transition(.opacity)
            }
        }
        .frame(width: layout.frame.width, height: height, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private func leftWing(_ content: NoticeContent) -> some View {
        HStack(spacing: 8) {
            if let face = content.face {
                Image(nsImage: MenuBarFace.faceImage(face, span: MenuBarFace.span(of: [face]), offset: .zero))
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 12)
                    .foregroundStyle(.white.opacity(0.9))
            }
            Text(content.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.leading, 16)
    }

    private func rightWing(_ content: NoticeContent) -> some View {
        HStack(spacing: 8) {
            if let detail = content.detail {
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
            if let end = content.countdownTo {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(BreakCycleState.clockString(end.timeIntervalSince(context.date)))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.trailing, 16)
    }
}

// MARK: - Window

/// A borderless window that's allowed to sit over the menu bar, where the
/// notch is. Never takes focus.
final class IslandPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .none
        // Above the menu bar and its icons.
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    /// AppKit would push a window out from under the menu bar; this one
    /// belongs there.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Shows the island. One at a time: a new one swaps its text in place. Click
/// it to tuck it away.
@MainActor
final class NoticePillController {
    static let shared = NoticePillController()

    private var panel: IslandPanel?
    private let model = IslandModel()
    private var hideTask: Task<Void, Never>?
    private var generation = 0

    private static let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.78)
    private static let closeAnimation = Animation.spring(response: 0.32, dampingFraction: 0.9)

    private init() {}

    func show(_ content: NoticeContent) {
        let panel = ensurePanel()
        generation += 1
        let mine = generation
        hideTask?.cancel()

        if panel.isVisible, model.isOpen {
            // Already out: just change the words.
            withAnimation(.easeInOut(duration: 0.2)) { model.content = content }
        } else {
            let layout = Self.currentLayout()
            model.layout = layout
            model.isOpen = false
            model.content = content
            panel.setFrame(layout.frame, display: true)
            panel.orderFrontRegardless()
            // Grow out of the notch on the next frame, so the closed shape
            // is drawn first and the change animates.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(20))
                guard let self, self.generation == mine else { return }
                withAnimation(Self.openAnimation) { self.model.isOpen = true }
            }
        }

        if !content.sticky {
            let seconds = content.duration
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                self?.hide(ifGeneration: mine)
            }
        }
    }

    func hide() {
        hide(ifGeneration: nil)
    }

    private func hide(ifGeneration expected: Int?) {
        guard let panel, panel.isVisible else { return }
        if let expected, expected != generation { return } // replaced by a newer one
        hideTask?.cancel()
        generation += 1
        let mine = generation
        withAnimation(Self.closeAnimation) { model.isOpen = false }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(380))
            guard let self, self.generation == mine else { return } // shown again meanwhile
            self.panel?.orderOut(nil)
            self.model.content = nil
        }
    }

    private func ensurePanel() -> IslandPanel {
        if let panel { return panel }
        let layout = Self.currentLayout()
        let newPanel = IslandPanel(contentRect: layout.frame)
        let view = NSHostingView(rootView: IslandView(model: model, onTap: { [weak self] in self?.hide() }))
        view.frame = NSRect(origin: .zero, size: layout.frame.size)
        view.autoresizingMask = [.width, .height]
        newPanel.contentView = view
        panel = newPanel
        model.layout = layout
        return newPanel
    }

    /// The screen being used; on a MacBook that's the one with the notch.
    private static func currentLayout() -> IslandGeometry.Layout {
        let screen = NSScreen.main ?? NSScreen.screens.first
        return IslandGeometry.layout(screenFrame: screen?.frame ?? .zero, notch: screen?.notchSize ?? .zero)
    }
}
