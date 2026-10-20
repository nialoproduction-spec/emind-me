import AppKit
import Combine

/// A random little reaction the menu bar icon plays when the pointer hovers
/// over it. Each is a short sequence of the traced faces plus a tiny motion.
enum HoverReaction: String, CaseIterable {
    case happy, shocked, scared, silly, shy, dizzy, smug, huffy

    var beats: [(face: Face, duration: Double)] {
        switch self {
        case .happy:   return [(.happy, 0.35), (.squee, 0.3), (.happy, 0.6)]
        case .shocked: return [(.owo, 0.12), (.surprisedKiss, 0.55), (.owo, 0.6)]
        case .scared:  return [(.wail, 0.7), (.tearful, 0.6)]
        case .silly:   return [(.tongue, 0.4), (.meh, 0.3), (.tongue, 0.5)]
        case .shy:     return [(.sheepish, 0.6), (.snout, 0.6)]
        case .dizzy:   return [(.dizzy, 1.0)]
        case .smug:    return [(.smug, 0.45), (.grin, 0.6)]
        case .huffy:   return [(.pout, 0.45), (.grumpy, 0.6)]
        }
    }

    var duration: Double { beats.reduce(0) { $0 + $1.duration } }

    /// Which face at `t` seconds in; holds the last face once it's played.
    func face(at t: Double) -> Face {
        var remaining = max(0, t)
        for beat in beats {
            if remaining < beat.duration { return beat.face }
            remaining -= beat.duration
        }
        return beats.last!.face
    }

    /// A small offset in points, so the face hops, jumps, shivers or sways.
    func motion(at t: Double) -> CGPoint {
        let tau = 2 * Double.pi
        switch self {
        case .happy, .silly, .smug, .shy:
            let decay = max(0, 1 - t / 0.8)
            return CGPoint(x: 0, y: -1.6 * abs(sin(Double.pi * t / 0.22)) * decay)
        case .shocked:
            return CGPoint(x: 0, y: t < 0.3 ? -2.2 * sin(Double.pi * t / 0.3) : 0)
        case .scared, .huffy:
            let decay = max(0, 1 - t / 0.6)
            return CGPoint(x: 1.2 * sin(tau * 10 * t) * decay, y: 0)
        case .dizzy:
            return CGPoint(x: t < 1.0 ? 1.0 * sin(tau * t / 0.5) : 0, y: 0)
        }
    }

    /// A different reaction from last time, so it doesn't feel repetitive.
    static func random(excluding previous: HoverReaction?) -> HoverReaction {
        let choices = allCases.filter { $0 != previous }
        return choices.randomElement() ?? .happy
    }
}

/// Draws and animates the menu bar icon:
/// - idle: the —ω— logo, unchanged (it's the sleepy face);
/// - pointer comes near: it wakes up happy (^ ^), then its little shiny
///   eyes follow the pointer wherever it goes, blinking now and then, and
///   it blushes when the pointer is right next to it; falls back asleep a
///   moment after the pointer leaves;
/// - pointer over it: wakes up with a random reaction, then back to the logo
///   once the pointer leaves;
/// - a reminder waiting for an answer: shows that reminder's mood face
///   (cute → pouty → angry as it nags), so it's obvious something's due.
/// Template images throughout, so it follows light and dark menu bars.
@MainActor
final class MenuBarFace {
    /// Fixed image size for every frame, so the menu bar never shifts.
    nonisolated static let imageSize = NSSize(width: 38, height: 20)
    nonisolated private static let drawBox = CGSize(width: 34, height: 16)

    private weak var button: NSStatusBarButton?
    private var hoverTarget: HoverTarget?
    private var cancellables = Set<AnyCancellable>()
    private var loop: Task<Void, Never>?

    private enum State {
        case idle
        case watching
        case hover(HoverReaction, start: Date)
        case reminder(FaceMood, start: Date)
    }
    private var proximity: Task<Void, Never>?
    private var wokeAt = Date.distantPast
    private var lastNear = Date.distantPast

    /// How close (in points) the pointer has to come to wake it.
    nonisolated static let wakeDistance: CGFloat = 220
    /// Asleep again this long after the pointer has gone.
    nonisolated static let sleepAfter: TimeInterval = 1.4
    private var state: State = .idle
    private var pointerInside = false
    private var lastReaction: HoverReaction?
    private var lastDrawn: String?

    func attach(to button: NSStatusBarButton) {
        self.button = button
        button.imagePosition = .imageOnly
        show(key: "logo", image: Self.logoImage())

        // .activeAlways: this is a menu bar app, so it's never the active app.
        let target = HoverTarget(
            onEnter: { [weak self] in self?.pointerEntered() },
            onExit: { [weak self] in self?.pointerExited() }
        )
        button.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: target, userInfo: nil
        ))
        hoverTarget = target

        ReminderScheduler.shared.$activeOccurrence
            .receive(on: RunLoop.main)
            .sink { [weak self] occurrence in self?.reminderChanged(occurrence) }
            .store(in: &cancellables)

        // Watches where the pointer is: a cheap check ten times a second,
        // thirty while it's awake and following the pointer.
        proximity = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let wait = self.watchStep()
                try? await Task.sleep(for: .milliseconds(wait))
            }
        }
    }

    // MARK: - Watching the pointer

    private func watchStep() -> Int {
        guard AppSettings.face.value.followPointer,
              let frame = button?.window?.frame, frame.width > 0 else {
            if case .watching = state { goIdle() }
            return 400
        }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - frame.midX
        let dy = mouse.y - frame.midY
        let distance = hypot(dx, dy)
        let near = distance < Self.wakeDistance
        let now = Date()
        if near { lastNear = now }

        switch state {
        case .idle:
            guard near else { return 100 }
            state = .watching
            wokeAt = now
            drawWatching(dx: dx, dy: dy, now: now)
            return 33
        case .watching:
            if !near, now.timeIntervalSince(lastNear) > Self.sleepAfter {
                goIdle()
                return 100
            }
            drawWatching(dx: dx, dy: dy, now: now)
            return 33
        case .hover, .reminder:
            return 150 // those draw themselves
        }
    }

    private func drawWatching(dx: CGFloat, dy: CGFloat, now: Date) {
        let awake = now.timeIntervalSince(wokeAt)
        let look = Self.look(dx: dx, dy: dy)
        let wow = awake < 0.6
        // A quick blink every ~4 seconds.
        let blink = !wow && awake.truncatingRemainder(dividingBy: 4.1) > 3.97
        // Right next to it: it gets shy and blushes.
        let shy = !wow && hypot(dx, dy) < 45
        show(key: "watch|\(Int(look.dx * 8))|\(Int(look.dy * 8))|\(blink)|\(wow)|\(shy)",
             image: Self.watchImage(look: look, blink: blink, wow: wow, shy: shy))
    }

    /// Where the pupils point: toward the pointer (screen y is up, the image
    /// is drawn y-down), full strength once it's more than ~60 pt away.
    nonisolated static func look(dx: CGFloat, dy: CGFloat) -> CGVector {
        let distance = hypot(dx, dy)
        guard distance > 0.5 else { return .zero }
        let strength = min(1, distance / 60)
        return CGVector(dx: dx / distance * strength, dy: -dy / distance * strength)
    }

    /// The awake face for the menu bar, kaomoji-cute (•ω•): two small round
    /// eyes with a shine that glance toward the pointer (`look`, each axis
    /// -1…1), a tiny ω mouth. Just woken (`wow`): happy ^ ^ eyes and an open
    /// little mouth. Blinking: closed ◡ eyes. Pointer very close (`shy`):
    /// it blushes and smiles.
    nonisolated static func watchImage(look: CGVector, blink: Bool, wow: Bool, shy: Bool = false) -> NSImage {
        template { ctx, _ in
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            let shift = CGPoint(x: look.dx * 1.7, y: look.dy * 1.2)
            let eyes = [CGPoint(x: 13 + shift.x, y: 9.5 + shift.y), CGPoint(x: 25 + shift.x, y: 9.5 + shift.y)]
            for eye in eyes {
                if wow {
                    // ^ ^
                    ctx.setLineWidth(1.6)
                    ctx.move(to: CGPoint(x: eye.x - 3, y: eye.y + 1.5))
                    ctx.addQuadCurve(to: CGPoint(x: eye.x + 3, y: eye.y + 1.5), control: CGPoint(x: eye.x, y: eye.y - 3.5))
                    ctx.strokePath()
                } else if blink {
                    // ◡ ◡
                    ctx.setLineWidth(1.6)
                    ctx.move(to: CGPoint(x: eye.x - 3, y: eye.y - 0.5))
                    ctx.addQuadCurve(to: CGPoint(x: eye.x + 3, y: eye.y - 0.5), control: CGPoint(x: eye.x, y: eye.y + 3))
                    ctx.strokePath()
                } else {
                    let r: CGFloat = 3.3
                    ctx.setBlendMode(.normal)
                    ctx.fillEllipse(in: CGRect(x: eye.x - r, y: eye.y - r, width: r * 2, height: r * 2))
                    // The shine, cut out of the eye.
                    ctx.setBlendMode(.clear)
                    let shine = CGPoint(x: eye.x + 1.1 - look.dx * 0.5, y: eye.y - 1.2)
                    ctx.fillEllipse(in: CGRect(x: shine.x - 1.05, y: shine.y - 1.05, width: 2.1, height: 2.1))
                    ctx.setBlendMode(.normal)
                }
                if shy {
                    // Blush: two little strokes under each eye.
                    ctx.setLineWidth(0.9)
                    for dx: CGFloat in [-1.8, 0.6] {
                        ctx.move(to: CGPoint(x: eye.x + dx - 0.7, y: 16.2))
                        ctx.addLine(to: CGPoint(x: eye.x + dx + 0.9, y: 14.2))
                    }
                    ctx.strokePath()
                }
            }
            let mouth = CGPoint(x: 19 + shift.x * 0.6, y: 14.6 + shift.y * 0.5)
            ctx.setLineWidth(1.25)
            if wow {
                // A little open ▽.
                ctx.move(to: CGPoint(x: mouth.x - 1.8, y: mouth.y - 0.4))
                ctx.addLine(to: CGPoint(x: mouth.x + 1.8, y: mouth.y - 0.4))
                ctx.addLine(to: CGPoint(x: mouth.x, y: mouth.y + 2))
                ctx.closePath()
                ctx.fillPath()
            } else if shy {
                ctx.move(to: CGPoint(x: mouth.x - 2, y: mouth.y))
                ctx.addQuadCurve(to: CGPoint(x: mouth.x + 2, y: mouth.y), control: CGPoint(x: mouth.x, y: mouth.y + 2.6))
                ctx.strokePath()
            } else {
                // ω
                ctx.move(to: CGPoint(x: mouth.x - 2.6, y: mouth.y))
                ctx.addQuadCurve(to: CGPoint(x: mouth.x, y: mouth.y + 0.3), control: CGPoint(x: mouth.x - 1.3, y: mouth.y + 2.4))
                ctx.addQuadCurve(to: CGPoint(x: mouth.x + 2.6, y: mouth.y), control: CGPoint(x: mouth.x + 1.3, y: mouth.y + 2.4))
                ctx.strokePath()
            }
        }
    }

    private func pointerEntered() {
        pointerInside = true
        // A waiting reminder's face takes priority; idle or watching, react.
        switch state {
        case .idle, .watching: break
        default: return
        }
        let reaction = HoverReaction.random(excluding: lastReaction)
        lastReaction = reaction
        state = .hover(reaction, start: Date())
        runLoop()
    }

    private func pointerExited() {
        pointerInside = false
        // If the reaction has finished, settle back to the logo now; otherwise
        // the loop does it when the reaction ends.
        if case .hover(let reaction, let start) = state, Date().timeIntervalSince(start) >= reaction.duration {
            goIdle()
        }
    }

    private func reminderChanged(_ occurrence: Occurrence?) {
        if let occurrence {
            let mood = FaceMood.forPop(
                count: occurrence.remindersSentCount,
                maxPops: EscalationSettingsStore.shared.settings.maxReminders
            )
            if case .reminder(let current, _) = state, current == mood { return }
            state = .reminder(mood, start: Date())
            button?.toolTip = "Remind Me — “\(occurrence.item?.title ?? "Reminder")” is waiting"
            runLoop()
        } else if case .reminder = state {
            button?.toolTip = "Remind Me"
            goIdle()
        }
    }

    private func goIdle() {
        state = .idle
        loop?.cancel()
        loop = nil
        show(key: "logo", image: Self.logoImage())
    }

    // MARK: - Animation loop (runs only while not idle)

    private func runLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = self.step()
                guard let interval else { return }
                try? await Task.sleep(for: .milliseconds(interval))
            }
        }
    }

    /// Draws the current frame; returns ms until the next one, or nil to stop.
    private func step() -> Int? {
        let now = Date()
        switch state {
        case .idle, .watching:
            return nil
        case .hover(let reaction, let start):
            let t = now.timeIntervalSince(start)
            let face = reaction.face(at: t)
            let offset = reaction.motion(at: t)
            let span = Self.span(of: reaction.beats.map { $0.face })
            show(key: "\(face)|\(Int(offset.x * 4))|\(Int(offset.y * 4))",
                 image: Self.faceImage(face, span: span, offset: offset))
            if t >= reaction.duration {
                if pointerInside { return nil } // hold the last face while hovered
                goIdle()
                return nil
            }
            return 40 // ~25 fps, only for the ~1 s the reaction lasts
        case .reminder(let mood, let start):
            let face = FaceScript.face(for: mood, at: now.timeIntervalSince(start))
            let span = Self.span(of: FaceScript.beats(for: mood).map { $0.face })
            show(key: "\(face)", image: Self.faceImage(face, span: span, offset: .zero))
            return 150 // expression swaps only — cheap enough to run while it waits
        }
    }

    private func show(key: String, image: NSImage) {
        guard key != lastDrawn else { return }
        lastDrawn = key
        button?.image = image
    }

    // MARK: - Drawing

    /// The —ω— logo, exactly as before.
    nonisolated static func logoImage() -> NSImage {
        let logo = FaceShapes.logo
        let box = logo.boundingBoxOfPath
        let scale = drawBox.width / box.width
        return template { ctx, rect in
            ctx.translateBy(x: (rect.width - box.width * scale) / 2, y: (rect.height - box.height * scale) / 2)
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -box.minX, y: -box.minY)
            fill(logo, in: ctx, embolden: 0.6 / scale)
        }
    }

    /// One face, scaled so every face in its sequence shares a size and centre.
    nonisolated static func faceImage(_ face: Face, span: CGRect, offset: CGPoint) -> NSImage {
        let scale = min(drawBox.width / span.width, drawBox.height / span.height)
        let strokes = FaceShapes.strokes(face)
        let tears = FaceShapes.tears(face)
        return template { ctx, rect in
            ctx.translateBy(x: rect.width / 2 + offset.x, y: rect.height / 2 + offset.y)
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -span.midX, y: -span.midY)
            if let tears { fill(tears, in: ctx, embolden: 0) }
            fill(strokes, in: ctx, embolden: 0.5 / scale)
        }
    }

    /// Combined bounds of a set of faces, in canvas units.
    nonisolated static func span(of faces: [Face]) -> CGRect {
        faces.reduce(CGRect.null) { box, face in
            var box = box.union(FaceShapes.strokes(face).boundingBoxOfPath)
            if let tears = FaceShapes.tears(face) { box = box.union(tears.boundingBoxOfPath) }
            return box
        }
    }

    nonisolated private static func fill(_ path: CGPath, in ctx: CGContext, embolden lineWidth: CGFloat) {
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.addPath(path)
        ctx.fillPath(using: .evenOdd)
        guard lineWidth > 0 else { return }
        // At menu bar size the traced lines are thin; thicken them a touch.
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineJoin(.round)
        ctx.addPath(path)
        ctx.strokePath()
    }

    nonisolated private static func template(_ draw: @escaping (CGContext, NSRect) -> Void) -> NSImage {
        let image = NSImage(size: imageSize, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(ctx, rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Remind Me"
        return image
    }
}

/// Receives the hover events for the menu bar button.
private final class HoverTarget: NSResponder {
    private let onEnter: @MainActor () -> Void
    private let onExit: @MainActor () -> Void

    init(onEnter: @escaping @MainActor () -> Void, onExit: @escaping @MainActor () -> Void) {
        self.onEnter = onEnter
        self.onExit = onExit
        super.init()
    }

    required init?(coder: NSCoder) { nil }

    override func mouseEntered(with event: NSEvent) { onEnter() }
    override func mouseExited(with event: NSEvent) { onExit() }
}
