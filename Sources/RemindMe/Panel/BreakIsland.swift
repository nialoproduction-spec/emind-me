import AppKit
import Combine
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

// MARK: - Rules

/// Which colours the notch uses.
enum IslandTone: String, Codable { case work, onBreak, away }

/// The notch's colours for one state: the glass tint, its text, the time,
/// and (away) the left side's alarm colour.
struct IslandPalette: Equatable {
    var background: RGBColor
    var text: RGBColor
    var time: RGBColor
    /// Away after a break: the left side turns this colour (red) and pulses.
    var leftWing: RGBColor? = nil
    /// Text on the left side (differs from `text` when `leftWing` is set).
    var leftText: RGBColor
}

@MainActor
enum BreakIslandRules {
    /// Working: the work colour (black by default). Break: the break colour
    /// (soft blue). Away after a break: the work colour with the time away in
    /// the away colour (red). Text turns dark on light colours.
    nonisolated static func palette(for tone: IslandTone, settings: BreakTimerSettings) -> IslandPalette {
        func onTop(_ background: RGBColor) -> RGBColor { background.isLight ? .ink : .white }
        switch tone {
        case .work:
            let text = onTop(settings.workColor)
            return IslandPalette(background: settings.workColor, text: text, time: text, leftText: text)
        case .onBreak:
            let text = onTop(settings.breakColor)
            return IslandPalette(background: settings.breakColor, text: text, time: text, leftText: text)
        case .away:
            let text = onTop(settings.workColor)
            return IslandPalette(background: settings.workColor, text: text, time: settings.awayColor,
                                 leftWing: settings.awayColor, leftText: onTop(settings.awayColor))
        }
    }

    /// On a break the title gently cycles through these, one every few
    /// seconds, so the break feels like a break.
    static let breakPrompts = ["Break", "Breathe in", "Look away", "Stretch",
                               "Sip water", "Rest your eyes", "Relax your jaw"]
    static let promptSeconds: TimeInterval = 9

    /// Whether the running timer stays at the notch between the moments it
    /// announces. Breaks (and "Break over") always do; the work countdown
    /// only when it's kept there.
    static func showsAmbient(phase: BreakCycleState.Phase, keepWorkCountdown: Bool) -> Bool {
        phase != .work || keepWorkCountdown
    }

    /// What the notch shows for the running timer's state.
    static func content(for state: BreakCycleState) -> NoticeContent {
        switch state.phase {
        case .work:
            return NoticeContent(title: "Working", countdownTo: state.phaseEnd, face: .smug, tone: .work, sticky: true)
        case .onBreak:
            return NoticeContent(title: "Break", countdownTo: state.phaseEnd, face: .sleepy, tone: .onBreak, sticky: true)
        case .waiting:
            return BreakCycleManager.waitingNotice(for: state)
        }
    }
}

// MARK: - Model + view

@MainActor
final class IslandModel: ObservableObject {
    @Published var isOpen = false
    @Published var wing: CGFloat = 0
    @Published var notch = IslandGeometry.notch(.zero)
    /// What's showing: face + title left of the notch, detail / countdown right.
    @Published var content: NoticeContent?
    @Published var palette = BreakIslandRules.palette(for: .work, settings: BreakTimerSettings())
}

/// The island: liquid glass tinted per state (black working, soft blue on a
/// break), face + title left of the notch, the time right of it. Away after
/// a break, the left side turns red and pulses while an angry face shakes.
struct IslandView: View {
    @ObservedObject var model: IslandModel
    var onTap: () -> Void = {}

    var body: some View {
        let notch = model.notch
        let wing = model.isOpen ? model.wing : 0
        let palette = model.palette
        let onBreak = model.content?.tone == .onBreak
        ZStack(alignment: .top) {
            IslandSurface(palette: palette, wing: wing, middle: notch.middleWidth, breathing: onBreak)
                .frame(width: notch.middleWidth + wing * 2, height: notch.height)
                .opacity(model.isOpen || notch.hasNotch ? 1 : 0)

            if let content = model.content {
                HStack(spacing: 0) {
                    HStack(spacing: 7) {
                        if let face = content.face { IslandFace(face: face, tone: content.tone ?? .work) }
                        if onBreak && content.title == "Break" {
                            BreakPrompt()
                        } else {
                            Text(content.title)
                                .font(.system(size: IslandGeometry.font, weight: .semibold, design: .rounded))
                        }
                    }
                    .foregroundStyle(palette.leftText.color)
                    .lineLimit(1)
                    .padding(.trailing, IslandGeometry.innerGap)
                    .frame(width: wing, alignment: .trailing)

                    Color.clear.frame(width: notch.middleWidth)

                    HStack(spacing: 7) {
                        if let detail = content.detail {
                            Text(detail)
                                .font(.system(size: IslandGeometry.font, design: .rounded))
                                .foregroundStyle(palette.text.color.opacity(0.8))
                        }
                        if let end = content.countdownTo { Countdown(end: end, color: palette.time.color) }
                        if let start = content.countUpFrom { CountUp(start: start, color: palette.time.color) }
                    }
                    .lineLimit(1)
                    .padding(.leading, IslandGeometry.innerGap)
                    .frame(width: wing, alignment: .leading)
                }
                .frame(height: notch.height)
                .opacity(model.isOpen ? 1 : 0)
                .id("\(content.title)|\(content.detail ?? "")|\(content.countdownTo?.timeIntervalSinceReferenceDate ?? 0)")
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

/// "Break", then "Breathe in", "Look far away"… one every few seconds,
/// fading from one to the next.
private struct BreakPrompt: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: BreakIslandRules.promptSeconds)) { context in
            let prompts = BreakIslandRules.breakPrompts
            let index = Int(context.date.timeIntervalSinceReferenceDate / BreakIslandRules.promptSeconds) % prompts.count
            Text(prompts[index])
                .font(.system(size: IslandGeometry.font, weight: .semibold, design: .rounded))
                .id(index)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.5), value: index)
        }
    }
}

/// The island's body: solid colour (so the colour you pick is the colour
/// you get), a faint sheen on top and a soft light along the bottom curve.
/// On a break it slowly breathes, brightening and dimming over 8 seconds.
/// Away after a break, the left side runs red and pulses.
struct IslandSurface: View {
    let palette: IslandPalette
    let wing: CGFloat
    let middle: CGFloat
    var breathing = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var breathe = false

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: IslandGeometry.cornerRadius,
            bottomTrailingRadius: IslandGeometry.cornerRadius,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(palette.background.color)
            if breathing {
                Rectangle().fill(Color.white.opacity(breathe ? 0.16 : 0))
            }
            if let alarm = palette.leftWing {
                Rectangle()
                    .fill(alarm.color.opacity(pulse ? 1 : 0.62))
                    .frame(width: wing + middle / 2)
                    .onAppear {
                        guard !reduceMotion else { pulse = true; return }
                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
                    }
            }
            LinearGradient(colors: [Color.white.opacity(0.07), Color.white.opacity(0)],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.5))
        }
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(
                LinearGradient(stops: [.init(color: .clear, location: 0),
                                       .init(color: .clear, location: 0.5),
                                       .init(color: Color.white.opacity(0.22), location: 1)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1
            )
        )
        .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
        .task(id: breathing) {
            guard breathing, !reduceMotion else { breathe = false; return }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}

/// The little face, alive: working, it blinks now and then; on a break it
/// bobs gently; away, it's furious and shakes. Still when Reduce Motion is on.
struct IslandFace: View {
    let face: Face
    let tone: IslandTone

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blinking = false
    @State private var bob = false
    @State private var shake: Double = 0

    var body: some View {
        FaceGlyph(face: blinking ? .sleepy : face)
            .offset(y: tone == .onBreak ? (bob ? -1.2 : 1.2) : 0)
            .rotationEffect(.degrees(shake))
            .overlay(alignment: .topTrailing) {
                if tone == .onBreak { FloatingZs().offset(x: 9, y: -5) }
            }
            .task(id: tone) { await animate() }
    }

    @MainActor private func animate() async {
        guard !reduceMotion else { return }
        switch tone {
        case .work:
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3.6))
                blinking = true
                try? await Task.sleep(for: .milliseconds(140))
                blinking = false
            }
        case .onBreak:
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { bob = true }
        case .away:
            while !Task.isCancelled {
                for angle in [-14.0, 12, -9, 6, 0] {
                    withAnimation(.easeInOut(duration: 0.07)) { shake = angle }
                    try? await Task.sleep(for: .milliseconds(70))
                }
                try? await Task.sleep(for: .seconds(1.6))
            }
        }
    }
}

/// Two little z's drifting up from a resting face.
private struct FloatingZs: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rise = false

    var body: some View {
        ZStack {
            z(size: 7, delay: 0)
            z(size: 5.5, delay: 1.1)
        }
        .onAppear {
            guard !reduceMotion else { return }
            rise = true
        }
    }

    private func z(size: CGFloat, delay: Double) -> some View {
        Text("z")
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .offset(x: rise ? 5 : 0, y: rise ? -9 : 0)
            .opacity(reduceMotion ? 0.8 : (rise ? 0 : 0.95))
            .animation(.easeOut(duration: 2.2).repeatForever(autoreverses: false).delay(delay), value: rise)
    }
}

private struct FaceGlyph: View {
    let face: Face
    var body: some View {
        Image(nsImage: MenuBarFace.faceImage(face, span: MenuBarFace.span(of: [face]), offset: .zero))
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: 13)
    }
}

private struct Countdown: View {
    let end: Date
    let color: Color
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(BreakCycleState.clockString(end.timeIntervalSince(context.date)))
                .font(.system(size: IslandGeometry.font, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
        }
    }
}

/// "+3:12", counting up: time away after a break.
private struct CountUp: View {
    let start: Date
    let color: Color
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(BreakCycleState.elapsedString(context.date.timeIntervalSince(start)))
                .font(.system(size: IslandGeometry.font, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
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

/// The break timer lives here, not in the menu bar: one look per state —
/// face + "Working" + countdown, face + "Break" + countdown, or "Break over ·
/// Waiting". The work countdown stays out if "keep at the notch" is on
/// (Settings, the list's pin, or the menu bar's right-click menu); if off, it
/// only peeks at the start, with 10 minutes left and for the last 10 seconds.
/// Clicking it while working hides it (turns "keep" off).
@MainActor
final class BreakIslandController {
    static let shared = BreakIslandController()

    private var panel: IslandPanel?
    private let model = IslandModel()
    private let settings = AppSettings.breakTimer
    /// The running timer, nil = none.
    private var state: BreakCycleState?
    /// A moment being shown on top of the usual state (for its duration).
    private var peek: NoticeContent?
    private var peekTask: Task<Void, Never>?
    private var generation = 0
    private var observers: [Any] = []

    private static let grow = Animation.spring(response: 0.4, dampingFraction: 0.8)
    private static let shrink = Animation.spring(response: 0.32, dampingFraction: 0.9)

    private init() {
        observers.append(settings.$value.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
    }

    /// The running timer (nil = none).
    func setAmbient(_ state: BreakCycleState?) {
        self.state = state
        if state == nil { clearPeek() }
        refresh()
    }

    /// A moment to show (start, 10 minutes left, last 10 seconds, break).
    func show(_ content: NoticeContent) {
        peekTask?.cancel()
        peek = content
        if !content.sticky {
            let seconds = content.duration
            let shown = content.id
            peekTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, let self, self.peek?.id == shown else { return }
                self.peek = nil
                self.refresh()
            }
        }
        refresh()
    }

    func hide() {
        clearPeek()
        refresh()
    }

    private func clearPeek() {
        peekTask?.cancel()
        peek = nil
    }

    /// Clicked: while working, put the countdown away (and keep it away).
    private func tapped() {
        if state?.phase == .work {
            settings.value.keepWorkCountdown = false
            clearPeek()
            refresh()
        } else if peek != nil {
            hide()
        }
    }

    /// What should be on screen right now.
    private var wanted: NoticeContent? {
        if let peek { return peek }
        guard let state,
              BreakIslandRules.showsAmbient(phase: state.phase, keepWorkCountdown: settings.value.keepWorkCountdown)
        else { return nil }
        return BreakIslandRules.content(for: state)
    }

    private func refresh() {
        let panel = ensurePanel()
        generation += 1
        let mine = generation
        let screen = Self.screen()
        model.notch = IslandGeometry.notch(screen?.notchSize ?? .zero)
        let screenFrame = screen?.frame ?? .zero

        guard let content = wanted else {
            guard panel.isVisible else { return }
            withAnimation(Self.shrink) { model.isOpen = false }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(380))
                guard let self, self.generation == mine else { return }
                self.panel?.orderOut(nil)
                self.model.content = nil
            }
            return
        }

        let wing = Self.wingWidth(for: content)
        // Grow the window first (the shape is centred, so it doesn't move),
        // animate the shape, then trim the window to fit.
        let roomy = max(wing, model.isOpen ? model.wing : 0)
        panel.setFrame(IslandGeometry.frame(screen: screenFrame, notch: model.notch, wing: roomy), display: true)

        let wasClosed = !panel.isVisible || !model.isOpen
        if !panel.isVisible {
            model.isOpen = false
            panel.orderFrontRegardless()
        }
        let palette = BreakIslandRules.palette(for: content.tone ?? .work, settings: settings.value)
        if wasClosed {
            model.wing = wing
            model.content = content
            model.palette = palette
        }
        Task { @MainActor [weak self] in
            if wasClosed { try? await Task.sleep(for: .milliseconds(20)) } // draw tucked-in first
            guard let self, self.generation == mine else { return }
            withAnimation(Self.grow) {
                self.model.isOpen = true
                self.model.wing = wing
                self.model.content = content
                self.model.palette = palette
            }
            try? await Task.sleep(for: .milliseconds(450))
            guard self.generation == mine else { return }
            self.panel?.setFrame(IslandGeometry.frame(screen: screenFrame, notch: self.model.notch, wing: wing), display: true)
        }
    }

    // MARK: - Sizing (what the text needs)

    static func wingWidth(for content: NoticeContent) -> CGFloat {
        let semibold = NSFont.systemFont(ofSize: IslandGeometry.font, weight: .semibold)
        let regular = NSFont.systemFont(ofSize: IslandGeometry.font)
        func width(_ text: String, _ font: NSFont) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: font]).width)
        }
        let gap: CGFloat = 7
        let titles = content.tone == .onBreak && content.title == "Break" ? BreakIslandRules.breakPrompts : [content.title]
        let left = (titles.map { width($0, semibold) }.max() ?? 0) + (content.face == nil ? 0 : 34 + gap)
        var right: CGFloat = 0
        if let detail = content.detail { right += width(detail, regular) }
        let digits = NSFont.monospacedDigitSystemFont(ofSize: IslandGeometry.font, weight: .bold)
        if let end = content.countdownTo {
            right += (right > 0 ? gap : 0) + width(end.timeIntervalSinceNow >= 3600 ? "0:00:00" : "00:00", digits)
        }
        if content.countUpFrom != nil {
            right += (right > 0 ? gap : 0) + width("+0:00:00", digits)
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
        let view = NSHostingView(rootView: IslandView(model: model, onTap: { [weak self] in self?.tapped() }))
        view.autoresizingMask = [.width, .height]
        newPanel.contentView = view
        panel = newPanel
        // Resolution or display changes: re-fit around the notch.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        return newPanel
    }
}
