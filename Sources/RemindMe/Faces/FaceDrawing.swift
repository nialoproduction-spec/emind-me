import SwiftUI
import AppKit

// MARK: - Path data -> shapes

/// Turns the traced outline strings in `FaceArt` into Core Graphics paths.
/// The data only ever uses absolute M / L / C / Z commands (that's all the
/// tracer emits), so this stays a tiny scanner rather than a full SVG parser.
enum SVGPathParser {
    static func cgPath(from data: String) -> CGPath {
        let path = CGMutablePath()
        var scanner = Scanner(bytes: Array(data.utf8))
        while let command = scanner.nextCommand() {
            switch command {
            case UInt8(ascii: "M"):
                path.move(to: scanner.point())
            case UInt8(ascii: "L"):
                path.addLine(to: scanner.point())
            case UInt8(ascii: "C"):
                let c1 = scanner.point(), c2 = scanner.point(), end = scanner.point()
                path.addCurve(to: end, control1: c1, control2: c2)
            case UInt8(ascii: "Z"):
                path.closeSubpath()
            default:
                break
            }
        }
        return path
    }

    private struct Scanner {
        let bytes: [UInt8]
        var index = 0

        mutating func nextCommand() -> UInt8? {
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                if (65...90).contains(byte) || (97...122).contains(byte) { return byte }
            }
            return nil
        }

        mutating func number() -> CGFloat {
            while index < bytes.count, bytes[index] == 32 || bytes[index] == 44 { index += 1 }
            let start = index
            if index < bytes.count, bytes[index] == 45 || bytes[index] == 43 { index += 1 }
            while index < bytes.count, (48...57).contains(bytes[index]) || bytes[index] == 46 { index += 1 }
            guard start < index,
                  let value = Double(String(decoding: bytes[start..<index], as: UTF8.self)) else { return 0 }
            return CGFloat(value)
        }

        mutating func point() -> CGPoint { CGPoint(x: number(), y: number()) }
    }
}

/// Parsed paths: all faces are parsed once, on first use, and then reused
/// for every frame. Immutable constants, so they're safe to read from
/// whichever thread SwiftUI happens to draw on.
enum FaceShapes {
    private static let allStrokes: [Face: CGPath] = Dictionary(
        uniqueKeysWithValues: Face.allCases.map { ($0, SVGPathParser.cgPath(from: FaceArt.strokesData($0))) }
    )
    private static let allTears: [Face: CGPath] = Dictionary(
        uniqueKeysWithValues: Face.allCases.compactMap { face in
            FaceArt.tearsData(face).map { (face, SVGPathParser.cgPath(from: $0)) }
        }
    )

    static func strokes(_ face: Face) -> CGPath { allStrokes[face] ?? CGMutablePath() }
    static func tears(_ face: Face) -> CGPath? { allTears[face] }

    static let logo: CGPath = SVGPathParser.cgPath(from: FaceArt.logoData)
}

// MARK: - A single face

/// Draws one face, scaled to fit, in the given colour. Tears keep their own
/// brown so the crying faces still read as crying on any theme.
struct FaceView: View {
    let face: Face
    var color: Color

    static let tearColor = Color(red: 0.55, green: 0.30, blue: 0.12)

    var body: some View {
        Canvas { context, size in
            let canvas = FaceArt.canvas
            let scale = min(size.width / canvas.width, size.height / canvas.height)
            let transform = CGAffineTransform(
                translationX: (size.width - canvas.width * scale) / 2,
                y: (size.height - canvas.height * scale) / 2
            ).scaledBy(x: scale, y: scale)

            if let tears = FaceShapes.tears(face) {
                context.fill(Path(tears).applying(transform), with: .color(Self.tearColor),
                             style: FillStyle(eoFill: true))
            }
            context.fill(Path(FaceShapes.strokes(face)).applying(transform), with: .color(color),
                         style: FillStyle(eoFill: true))
        }
        .aspectRatio(FaceArt.canvas.width / FaceArt.canvas.height, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// MARK: - Moods

/// How the reminder face behaves. The first three follow how many times it
/// has had to pop; the last three are the short reaction to a button.
enum FaceMood: Hashable, CaseIterable {
    case gentle   // first pop: cute, blinking
    case nudge    // middle pops: pouty, wiggling
    case urgent   // last pop: angry, shaking
    case done     // reaction to Done: happy hop
    case snoozed  // reaction to Snooze: dozes off
    case skipped  // reaction to Skip: cries

    /// Mood for a reminder that has popped `count` times out of `maxPops`.
    static func forPop(count: Int, maxPops: Int) -> FaceMood {
        if count <= 1 { return .gentle }
        if count >= maxPops { return .urgent }
        return .nudge
    }

    var isReaction: Bool { self == .done || self == .snoozed || self == .skipped }
}

/// One moment of the animation: which face, and how it's moved.
struct FaceFrame: Equatable {
    var face: Face
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    var rotation: Double = 0
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
}

/// The choreography for every mood: a sequence of faces (looped for the
/// three pop moods, played once then held for the reactions) plus a motion
/// curve. Pure function of time, so it's easy to preview and test.
enum FaceScript {
    typealias Beat = (face: Face, duration: Double)

    static func beats(for mood: FaceMood) -> [Beat] {
        switch mood {
        case .gentle:
            // Open eyes, then blink by swapping to the same face with closed eyes.
            return [(.owo, 2.2), (.sleepy, 0.13), (.owo, 1.6), (.sleepy, 0.12), (.owo, 0.22),
                    (.sleepy, 0.12), (.owo, 1.0), (.tiny, 1.3), (.snout, 1.2), (.sly, 1.2)]
        case .nudge:
            return [(.pout, 1.0), (.surprisedKiss, 0.8), (.pout, 0.5), (.smugKiss, 0.9),
                    (.blank, 0.9), (.unimpressed, 1.1), (.meh, 0.9), (.dizzy, 0.9)]
        case .urgent:
            return [(.grumpy, 0.9), (.annoyed, 1.0), (.furious, 0.8), (.smug, 0.7),
                    (.grumpy, 0.6), (.furious, 0.7)]
        case .done:
            return [(.happy, 0.22), (.squee, 0.22), (.tongue, 0.22), (.grin, 0.22), (.happy, .infinity)]
        case .snoozed:
            return [(.sheepish, 0.35), (.sleepy, .infinity)]
        case .skipped:
            return [(.tearful, 0.3), (.wail, 0.3), (.sob, .infinity)]
        }
    }

    static func frame(for mood: FaceMood, at time: Double, reduceMotion: Bool = false) -> FaceFrame {
        var frame = FaceFrame(face: face(for: mood, at: time))
        guard !reduceMotion else { return frame }
        let t = max(0, time)
        let tau = 2 * Double.pi

        switch mood {
        case .gentle:
            // Slow bob with a hint of squash at the bottom.
            let wave = sin(tau * t / 1.8)
            frame.dy = CGFloat(-2.5 * wave)
            frame.scaleY = CGFloat(1 + 0.025 * wave)
        case .nudge:
            // Side-to-side head tilt, a little hop on each side.
            let wave = sin(tau * t / 0.8)
            frame.rotation = 5 * wave
            frame.dy = CGFloat(-1.8 * abs(wave))
        case .urgent:
            // Bursts of shaking, then a beat of stillness.
            let phase = t.truncatingRemainder(dividingBy: 1.3)
            if phase < 0.45 {
                let fade = 1 - phase / 0.45
                frame.dx = CGFloat(3.5 * sin(tau * 9 * phase) * fade)
                frame.scaleX = CGFloat(1 + 0.04 * fade)
                frame.scaleY = CGFloat(1 + 0.04 * fade)
            }
        case .done:
            // Two quick hops that settle.
            let decay = max(0, 1 - t / 0.9)
            let hop = abs(sin(Double.pi * t / 0.3))
            frame.dy = CGFloat(-10 * hop * decay)
            frame.scaleY = CGFloat(1 + 0.06 * hop * decay)
            frame.scaleX = CGFloat(1 - 0.03 * hop * decay)
        case .snoozed:
            // Sinks a little and settles into slow breathing.
            let settle = min(t / 0.6, 1)
            frame.dy = CGFloat(4 * settle)
            frame.scaleY = CGFloat(1 - 0.04 * settle + 0.015 * sin(tau * t / 2.4) * settle)
        case .skipped:
            // A sob: fast tremble that fades while the face droops.
            let fade = max(0, 1 - t / 0.9)
            frame.dx = CGFloat(1.4 * sin(tau * 14 * t) * fade)
            frame.dy = CGFloat(3 * min(t / 0.5, 1))
        }
        return frame
    }

    /// Which face is showing at `time` seconds into the mood.
    static func face(for mood: FaceMood, at time: Double) -> Face {
        let beats = beats(for: mood)
        let loops = !mood.isReaction
        let total = beats.reduce(0) { $0 + $1.duration }
        var t = max(0, time)
        if loops, total.isFinite, total > 0 { t = t.truncatingRemainder(dividingBy: total) }
        for beat in beats {
            if t < beat.duration { return beat.face }
            t -= beat.duration
        }
        return beats.last?.face ?? .owo
    }
}

// MARK: - Layout

/// Sizing for the face in the reminder card. Every face is drawn at the same
/// scale; each mood's faces are centred as a group in a short window, so
/// small faces don't leave a big gap under them, the eye line stays put
/// within a mood, and the group glides to its new centre when a reaction
/// starts.
enum FaceLayout {
    static let faceWidth: CGFloat = 168
    static let windowHeight: CGFloat = 64
    static var scale: CGFloat { faceWidth / FaceArt.canvas.width }
    static var faceHeight: CGFloat { FaceArt.canvas.height * scale }

    /// Vertical span, in canvas units, of everything a mood can show.
    static func verticalSpan(of mood: FaceMood) -> ClosedRange<CGFloat> {
        spans[mood] ?? 0...FaceArt.canvas.height
    }

    /// How far to shift the full-size face so the mood's span sits centred
    /// in the window.
    static func offset(for mood: FaceMood) -> CGFloat {
        let span = verticalSpan(of: mood)
        return windowHeight / 2 - (span.lowerBound + span.upperBound) / 2 * scale
    }

    private static let spans: [FaceMood: ClosedRange<CGFloat>] = Dictionary(
        uniqueKeysWithValues: FaceMood.allCases.map { mood in
            var box = CGRect.null
            for beat in FaceScript.beats(for: mood) {
                box = box.union(FaceShapes.strokes(beat.face).boundingBoxOfPath)
                if let tears = FaceShapes.tears(beat.face) { box = box.union(tears.boundingBoxOfPath) }
            }
            return (mood, box.minY...box.maxY)
        }
    )
}

// MARK: - Animated face

/// The face shown in the live reminder. Fully animated (up to 30 fps) for a
/// few seconds whenever it appears, changes mood or nags again; after that it
/// settles into a calm mode that only swaps expressions a few times a second
/// — a reminder can now wait on screen for a long time, and this keeps that
/// nearly free on battery. Respects Reduce Motion: faces still change
/// expression, but nothing moves.
struct AnimatedFaceView: View {
    let mood: FaceMood
    var color: Color
    /// Changing this (e.g. each new nag) wakes the full animation back up.
    var wakeToken: Int = 0

    /// How long the full-motion animation runs before settling down.
    static let livelyDuration: Duration = .seconds(12)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var calm = false

    private struct WakeKey: Hashable {
        let mood: FaceMood
        let token: Int
    }

    var body: some View {
        Group {
            if calm {
                TimelineView(.periodic(from: start, by: 0.12)) { timeline in
                    face(at: timeline.date, still: true)
                }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    face(at: timeline.date, still: reduceMotion)
                }
            }
        }
        .frame(width: FaceLayout.faceWidth, height: FaceLayout.faceHeight)
        .offset(y: FaceLayout.offset(for: mood))
        .animation(reduceMotion ? nil : .spring(duration: 0.35), value: mood)
        .frame(width: FaceLayout.faceWidth, height: FaceLayout.windowHeight, alignment: .top)
        .allowsHitTesting(false)
        .task(id: WakeKey(mood: mood, token: wakeToken)) {
            start = Date()
            calm = false
            try? await Task.sleep(for: Self.livelyDuration)
            if !Task.isCancelled { calm = true }
        }
    }

    private func face(at date: Date, still: Bool) -> some View {
        let frame = FaceScript.frame(for: mood, at: date.timeIntervalSince(start), reduceMotion: still)
        return FaceView(face: frame.face, color: color)
            .scaleEffect(x: frame.scaleX, y: frame.scaleY, anchor: .bottom)
            .rotationEffect(.degrees(frame.rotation))
            .offset(x: frame.dx, y: frame.dy)
    }
}
