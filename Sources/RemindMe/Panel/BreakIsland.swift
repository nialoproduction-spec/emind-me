import AppKit
import SwiftUI

// MARK: - Geometry

/// The break timer's "island": a black shape around the camera notch, like
/// Dynamic Island. Pure maths here, so it's tested.
enum IslandGeometry {
    /// Screens without a notch: a small gap in the middle instead.
    static let noNotchGap: CGFloat = 16
    static let noNotchHeight: CGFloat = 32
    static let cornerRadius: CGFloat = 10
    /// Space between the text and the notch, and at the outer end.
    static let innerGap: CGFloat = 10
    static let outerPadding: CGFloat = 12
    static let minWing: CGFloat = 44
    static let maxWing: CGFloat = 200
    static let font: CGFloat = 13

    struct Notch: Equatable {
        var middleWidth: CGFloat
        var height: CGFloat
        var hasNotch: Bool
    }

    static func notch(_ size: CGSize) -> Notch {
        let hasNotch = size.width > 0 && size.height > 0
        return Notch(middleWidth: hasNotch ? size.width : noNotchGap,
                     height: hasNotch ? size.height : noNotchHeight,
                     hasNotch: hasNotch)
    }

    /// Each side is as wide as the wider side's content needs (so the shape
    /// stays centred on the notch), and the text sits right next to the notch.
    static func wingWidth(left: CGFloat, right: CGFloat) -> CGFloat {
        min(maxWing, max(minWing, max(left, right) + innerGap + outerPadding))
    }

    /// The window: centred on the screen's top edge, as tall as the notch.
    static func frame(screen: CGRect, notch: Notch, wing: CGFloat) -> CGRect {
        let width = notch.middleWidth + wing * 2
        return CGRect(x: screen.midX - width / 2, y: screen.maxY - notch.height, width: width, height: notch.height)
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

// MARK: - Model + view

@MainActor
final class IslandModel: ObservableObject {
    enum Mode { case hidden, compact, expanded }

    /// What the running timer shows when nothing's announced: a face (work)
    /// or "Break", and the countdown.
    struct Ambient: Equatable {
        var onBreak: Bool
        var end: Date
        /// Break's over, waiting for the person to come back.
        var waiting = false
    }

    @Published var mode: Mode = .hidden
    @Published var wing: CGFloat = 0
    @Published var notch = IslandGeometry.notch(.zero)
    @Published var ambient: Ambient?
    /// The moment being announced ("Break in · 0:05").
    @Published var expanded: NoticeContent?
}

struct IslandView: View {
    @ObservedObject var model: IslandModel
    var onTap: () -> Void = {}

    var body: some View {
        let notch = model.notch
        let wing = model.mode == .hidden ? 0 : model.wing
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: IslandGeometry.cornerRadius,
                bottomTrailingRadius: IslandGeometry.cornerRadius,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(Color.black)
            .frame(width: notch.middleWidth + wing * 2, height: notch.height)
            .opacity(model.mode != .hidden || notch.hasNotch ? 1 : 0)

            HStack(spacing: 0) {
                left
                    .padding(.trailing, IslandGeometry.innerGap)
                    .frame(width: wing, alignment: .trailing)
                Color.clear.frame(width: notch.middleWidth)
                right
                    .padding(.leading, IslandGeometry.innerGap)
                    .frame(width: wing, alignment: .leading)
            }
            .frame(height: notch.height)
            .clipped()
            .opacity(model.mode == .hidden ? 0 : 1)
            .id(contentKey)
            .transition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var contentKey: String {
        if model.mode == .expanded, let content = model.expanded { return content.id.uuidString }
        if model.ambient?.waiting == true { return "waiting" }
        return model.ambient?.onBreak == true ? "break" : "work"
    }

    @ViewBuilder
    private var left: some View {
        HStack(spacing: 7) {
            if model.mode == .expanded, let content = model.expanded {
                if let face = content.face { FaceGlyph(face: face) }
                Text(content.title)
                    .font(.system(size: IslandGeometry.font, weight: .semibold))
            } else if model.ambient?.waiting == true {
                FaceGlyph(face: .sleepy)
            } else if model.ambient?.onBreak == true {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("Break")
                    .font(.system(size: IslandGeometry.font, weight: .semibold))
            } else {
                FaceGlyph(face: .smug)
            }
        }
        .foregroundStyle(.white)
        .lineLimit(1)
    }

    @ViewBuilder
    private var right: some View {
        HStack(spacing: 7) {
            if model.mode == .expanded, let content = model.expanded {
                if let detail = content.detail {
                    Text(detail)
                        .font(.system(size: IslandGeometry.font))
                        .foregroundStyle(.white.opacity(0.85))
                }
                if let end = content.countdownTo { Countdown(end: end) }
            } else if let ambient = model.ambient {
                if ambient.waiting {
                    Text("Waiting")
                        .font(.system(size: IslandGeometry.font, weight: .semibold))
                        .foregroundStyle(.white)
                } else {
                    Countdown(end: ambient.end)
                }
            }
        }
        .lineLimit(1)
    }
}

private struct FaceGlyph: View {
    let face: Face
    var body: some View {
        Image(nsImage: MenuBarFace.faceImage(face, span: MenuBarFace.span(of: [face]), offset: .zero))
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: 11)
            .foregroundStyle(.white.opacity(0.95))
    }
}

private struct Countdown: View {
    let end: Date
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(BreakCycleState.clockString(end.timeIntervalSince(context.date)))
                .font(.system(size: IslandGeometry.font, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
        }
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

// MARK: - Controller

/// The break timer lives here, not in the menu bar. While a timer runs, the
/// island stays out small: a face (or "Break") left of the notch and the
/// countdown right of it. At the moments that matter it widens with words
/// ("Work · 40:00", "Last 10 minutes · 9:59", "Break in · 0:05",
/// "Time for a break · Rest for 10 minutes."), then shrinks back. Small mode
/// lets clicks through to the menu bar; a click on the wide one shrinks it.
@MainActor
final class BreakIslandController {
    static let shared = BreakIslandController()

    private var panel: IslandPanel?
    private let model = IslandModel()
    private var collapseTask: Task<Void, Never>?
    private var generation = 0
    private var screenObserver: NSObjectProtocol?

    private static let grow = Animation.spring(response: 0.4, dampingFraction: 0.8)
    private static let shrink = Animation.spring(response: 0.32, dampingFraction: 0.9)

    private init() {}

    /// The running timer (nil = none): shown small whenever nothing's announced.
    func setAmbient(_ state: BreakCycleState?) {
        let ambient = state.map {
            IslandModel.Ambient(onBreak: $0.phase == .onBreak, end: $0.phaseEnd, waiting: $0.phase == .waiting)
        }
        guard ambient != model.ambient || model.mode == .hidden else { return }
        model.ambient = ambient
        guard model.mode != .expanded else { return } // shrinks to the new state when it's done
        go(to: ambient == nil ? .hidden : .compact)
    }

    /// Announces a moment, wide, for its duration (or until replaced if sticky).
    func show(_ content: NoticeContent) {
        collapseTask?.cancel()
        model.expanded = content
        go(to: .expanded)
        guard !content.sticky else { return }
        let seconds = content.duration
        let shown = content.id
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.model.expanded?.id == shown else { return }
            self.collapse()
        }
    }

    /// Back to small (or away, with no timer running).
    func hide() { collapse() }

    private func collapse() {
        collapseTask?.cancel()
        model.expanded = nil
        go(to: model.ambient == nil ? .hidden : .compact)
    }

    private func go(to mode: IslandModel.Mode) {
        let panel = ensurePanel()
        generation += 1
        let mine = generation
        let screen = Self.screen()
        model.notch = IslandGeometry.notch(screen?.notchSize ?? .zero)
        let screenFrame = screen?.frame ?? .zero

        if mode == .hidden {
            guard panel.isVisible else { return }
            withAnimation(Self.shrink) { model.mode = .hidden }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(380))
                guard let self, self.generation == mine else { return }
                self.panel?.orderOut(nil)
            }
            return
        }

        let wing = wingWidth(for: mode)
        // Grow the window first (the shape is centred, so it doesn't move),
        // animate the shape, then trim the window to fit.
        let roomy = max(wing, model.mode == .hidden ? 0 : model.wing)
        panel.setFrame(IslandGeometry.frame(screen: screenFrame, notch: model.notch, wing: roomy), display: true)
        panel.ignoresMouseEvents = mode == .compact

        let wasHidden = !panel.isVisible || model.mode == .hidden
        if !panel.isVisible {
            model.mode = .hidden
            panel.orderFrontRegardless()
        }
        if wasHidden { model.wing = wing }
        Task { @MainActor [weak self] in
            if wasHidden { try? await Task.sleep(for: .milliseconds(20)) } // draw tucked-in first
            guard let self, self.generation == mine else { return }
            withAnimation(Self.grow) {
                self.model.mode = mode
                self.model.wing = wing
            }
            try? await Task.sleep(for: .milliseconds(450))
            guard self.generation == mine else { return }
            self.panel?.setFrame(IslandGeometry.frame(screen: screenFrame, notch: self.model.notch, wing: wing), display: true)
        }
    }

    // MARK: - Sizing (what the text needs)

    private func wingWidth(for mode: IslandModel.Mode) -> CGFloat {
        let semibold = NSFont.systemFont(ofSize: IslandGeometry.font, weight: .semibold)
        let regular = NSFont.systemFont(ofSize: IslandGeometry.font)
        func width(_ text: String, _ font: NSFont) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: font]).width)
        }
        func clock(_ end: Date) -> CGFloat {
            let digits = NSFont.monospacedDigitSystemFont(ofSize: IslandGeometry.font, weight: .semibold)
            return width(end.timeIntervalSinceNow >= 3600 ? "0:00:00" : "00:00", digits)
        }
        let faceWidth: CGFloat = 28
        let gap: CGFloat = 7

        var left: CGFloat = 0
        var right: CGFloat = 0
        if mode == .expanded, let content = model.expanded {
            left = width(content.title, semibold) + (content.face == nil ? 0 : faceWidth + gap)
            if let detail = content.detail { right += width(detail, regular) }
            if let end = content.countdownTo { right += (right > 0 ? gap : 0) + clock(end) }
        } else if let ambient = model.ambient {
            left = ambient.onBreak ? 14 + gap + width("Break", semibold) : faceWidth
            right = ambient.waiting ? width("Waiting", semibold) : clock(ambient.end)
        }
        return IslandGeometry.wingWidth(left: left, right: right)
    }

    /// The notch screen if there is one (a MacBook's built-in display),
    /// otherwise the main screen.
    private static func screen() -> NSScreen? {
        NSScreen.screens.first { $0.notchSize.width > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func ensurePanel() -> IslandPanel {
        if let panel { return panel }
        let newPanel = IslandPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 32))
        let view = NSHostingView(rootView: IslandView(model: model, onTap: { [weak self] in self?.hide() }))
        view.autoresizingMask = [.width, .height]
        newPanel.contentView = view
        panel = newPanel
        // Resolution or display changes: re-fit around the notch.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.model.mode != .hidden else { return }
                self.go(to: self.model.mode)
            }
        }
        return newPanel
    }
}
