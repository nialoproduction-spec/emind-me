import SwiftUI

/// Faces built from parts — eyes × mouth × an extra (tears, blush, anger
/// mark…) — drawn in the same thick white line style as the traced faces, on
/// the same 200 × 104 canvas. 18 eyes × 16 mouths × 7 extras = 2,016 faces.
/// Each part has moods, so a face can be asked for by feeling.
struct Kaomoji: Hashable {
    enum Eyes: Int, CaseIterable {
        case dot, bead, ring, wide, line, happy, worried, caret, squint, cross,
             spiral, angry, crying, star, heart, wink, sheepish, content
    }

    enum Mouth: Int, CaseIterable {
        case cat, smile, open, frown, flat, small, gasp, kiss, squee, grin,
             wavy, teeth, square, tongue, rage, meh
    }

    enum Extra: Int, CaseIterable {
        case none, blush, tears, sweat, anger, sparkles, sleep
    }

    enum Mood: CaseIterable {
        case happy, calm, angry, sad, shocked, dead, love
    }

    var eyes: Eyes
    var mouth: Mouth
    var extra: Extra

    static let count = Eyes.allCases.count * Mouth.allCases.count * Extra.allCases.count

    /// Every face, in a fixed order (for the catalog).
    static func at(_ index: Int) -> Kaomoji {
        let e = Eyes.allCases.count, m = Mouth.allCases.count
        let i = ((index % count) + count) % count
        return Kaomoji(eyes: Eyes.allCases[i % e],
                       mouth: Mouth.allCases[(i / e) % m],
                       extra: Extra.allCases[i / (e * m)])
    }

    // MARK: - Moods

    private static let pools: [Mood: (eyes: [Eyes], mouths: [Mouth], extras: [Extra])] = [
        .happy: ([.dot, .bead, .happy, .caret, .squint, .star, .wink, .content],
                 [.cat, .smile, .open, .grin, .tongue, .squee],
                 [.none, .none, .blush, .sparkles]),
        .calm: ([.line, .content, .sheepish, .bead, .happy],
                [.cat, .smile, .flat, .small],
                [.none, .sleep, .blush]),
        .angry: ([.angry, .squint, .line],
                 [.frown, .teeth, .rage, .square, .flat],
                 [.anger, .anger, .none, .sweat]),
        .sad: ([.worried, .crying, .ring, .bead],
               [.frown, .wavy, .square, .small, .meh],
               [.tears, .tears, .sweat, .none]),
        .shocked: ([.wide, .ring, .dot, .worried],
                   [.gasp, .small, .wavy, .square],
                   [.sweat, .none, .tears]),
        .dead: ([.cross, .spiral],
                [.wavy, .flat, .gasp, .tongue, .square],
                [.none, .sweat, .tears]),
        .love: ([.heart, .happy, .star, .content],
                [.smile, .kiss, .cat, .open],
                [.blush, .sparkles, .blush]),
    ]

    static func random(_ mood: Mood) -> Kaomoji {
        var rng = SystemRandomNumberGenerator()
        return random(mood, using: &rng)
    }

    static func random<R: RandomNumberGenerator>(_ mood: Mood, using rng: inout R) -> Kaomoji {
        let pool = pools[mood]!
        return Kaomoji(eyes: pool.eyes.randomElement(using: &rng)!,
                       mouth: pool.mouths.randomElement(using: &rng)!,
                       extra: pool.extras.randomElement(using: &rng)!)
    }

    /// How many different faces a mood can make.
    static func variety(_ mood: Mood) -> Int {
        let pool = pools[mood]!
        return Set(pool.eyes).count * Set(pool.mouths).count * Set(pool.extras).count
    }

    // MARK: - Drawing

    static let canvas = CGSize(width: 200, height: 104)
    static let lineWidth: CGFloat = 5

    struct Stroke {
        var path: Path
        var filled: Bool
    }

    private static let left = CGPoint(x: 54, y: 40)
    private static let right = CGPoint(x: 146, y: 40)

    /// The lines that make up this face, in canvas units.
    var strokes: [Stroke] {
        var all: [Stroke] = []
        all += Self.eye(eyes, at: Self.left, side: -1)
        all += Self.eye(eyes == .wink ? .caret : eyes, at: Self.right, side: 1)
        all += Self.mouth(mouth)
        all += Self.extra(extra)
        return all
    }

    private static func line(_ points: [CGPoint]) -> Stroke {
        var p = Path()
        p.addLines(points)
        return Stroke(path: p, filled: false)
    }

    private static func circle(_ c: CGPoint, _ r: CGFloat, filled: Bool) -> Stroke {
        Stroke(path: Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), filled: filled)
    }

    private static func curve(_ a: CGPoint, _ control: CGPoint, _ b: CGPoint) -> Stroke {
        var p = Path()
        p.move(to: a)
        p.addQuadCurve(to: b, control: control)
        return Stroke(path: p, filled: false)
    }

    /// `side`: -1 for the left eye, +1 for the right (the inner side faces
    /// the middle), so slanted parts mirror.
    private static func eye(_ eyes: Eyes, at c: CGPoint, side: CGFloat) -> [Stroke] {
        let inner = -side // direction toward the middle
        switch eyes {
        case .dot: return [circle(c, 11, filled: true)]
        case .bead: return [circle(CGPoint(x: c.x, y: c.y + 2), 6.5, filled: true)]
        case .ring: return [circle(c, 12, filled: false)]
        case .wide:
            return [circle(c, 17, filled: false), circle(CGPoint(x: c.x, y: c.y + 2), 6, filled: true)]
        case .line:
            return [line([CGPoint(x: c.x - 20, y: c.y), CGPoint(x: c.x + 20, y: c.y)])]
        case .happy:
            return [curve(CGPoint(x: c.x - 17, y: c.y + 7), CGPoint(x: c.x, y: c.y - 19), CGPoint(x: c.x + 17, y: c.y + 7))]
        case .content:
            return [curve(CGPoint(x: c.x - 17, y: c.y - 4), CGPoint(x: c.x, y: c.y + 16), CGPoint(x: c.x + 17, y: c.y - 4))]
        case .worried:
            return [
                circle(CGPoint(x: c.x, y: c.y + 6), 6.5, filled: true),
                line([CGPoint(x: c.x - 16 * inner, y: c.y - 8), CGPoint(x: c.x + 13 * inner, y: c.y - 19)]),
            ]
        case .angry:
            return [
                circle(CGPoint(x: c.x, y: c.y + 6), 7.5, filled: true),
                line([CGPoint(x: c.x - 18 * inner, y: c.y - 20), CGPoint(x: c.x + 14 * inner, y: c.y - 7)]),
            ]
        case .caret:
            return [line([CGPoint(x: c.x - 15, y: c.y + 7), CGPoint(x: c.x, y: c.y - 9), CGPoint(x: c.x + 15, y: c.y + 7)])]
        case .squint:
            // ">" on the left, "<" on the right.
            return [line([CGPoint(x: c.x - 12 * inner, y: c.y - 12), CGPoint(x: c.x + 12 * inner, y: c.y),
                          CGPoint(x: c.x - 12 * inner, y: c.y + 12)])]
        case .cross:
            return [line([CGPoint(x: c.x - 12, y: c.y - 12), CGPoint(x: c.x + 12, y: c.y + 12)]),
                    line([CGPoint(x: c.x + 12, y: c.y - 12), CGPoint(x: c.x - 12, y: c.y + 12)])]
        case .spiral:
            var p = Path()
            let turns: CGFloat = 2.4
            let steps = 60
            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let angle = t * turns * 2 * .pi * side
                let r = 2 + 13 * t
                let point = CGPoint(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r)
                if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
            }
            return [Stroke(path: p, filled: false)]
        case .crying:
            return [line([CGPoint(x: c.x - 17, y: c.y - 9), CGPoint(x: c.x + 17, y: c.y - 9)]),
                    line([CGPoint(x: c.x, y: c.y - 9), CGPoint(x: c.x, y: c.y + 15)])]
        case .star:
            var p = Path()
            for i in 0..<10 {
                let r: CGFloat = i % 2 == 0 ? 15 : 6.5
                let angle = CGFloat(i) * .pi / 5 - .pi / 2
                let point = CGPoint(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r)
                if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
            }
            p.closeSubpath()
            return [Stroke(path: p, filled: true)]
        case .heart:
            var p = Path()
            let top = CGPoint(x: c.x, y: c.y - 5)
            p.move(to: CGPoint(x: c.x, y: c.y + 13))
            p.addCurve(to: CGPoint(x: c.x - 15, y: c.y - 6), control1: CGPoint(x: c.x - 8, y: c.y + 6),
                       control2: CGPoint(x: c.x - 16, y: c.y + 2))
            p.addCurve(to: top, control1: CGPoint(x: c.x - 14, y: c.y - 16), control2: CGPoint(x: c.x - 3, y: c.y - 15))
            p.addCurve(to: CGPoint(x: c.x + 15, y: c.y - 6), control1: CGPoint(x: c.x + 3, y: c.y - 15),
                       control2: CGPoint(x: c.x + 14, y: c.y - 16))
            p.addCurve(to: CGPoint(x: c.x, y: c.y + 13), control1: CGPoint(x: c.x + 16, y: c.y + 2),
                       control2: CGPoint(x: c.x + 8, y: c.y + 6))
            p.closeSubpath()
            return [Stroke(path: p, filled: true)]
        case .wink:
            return [circle(c, 11, filled: true)]
        case .sheepish:
            return ([-8, 0, 8] as [CGFloat]).map { dy in
                line([CGPoint(x: c.x - 15, y: c.y + dy), CGPoint(x: c.x + 15, y: c.y + dy)])
            }
        }
    }

    private static func mouth(_ mouth: Mouth) -> [Stroke] {
        let m = CGPoint(x: 100, y: 62)
        switch mouth {
        case .cat:
            return [curve(CGPoint(x: m.x - 18, y: m.y - 6), CGPoint(x: m.x - 9, y: m.y + 14), CGPoint(x: m.x, y: m.y - 3)),
                    curve(CGPoint(x: m.x, y: m.y - 3), CGPoint(x: m.x + 9, y: m.y + 14), CGPoint(x: m.x + 18, y: m.y - 6))]
        case .smile:
            return [curve(CGPoint(x: m.x - 13, y: m.y - 5), CGPoint(x: m.x, y: m.y + 13), CGPoint(x: m.x + 13, y: m.y - 5))]
        case .open:
            var p = Path()
            p.addLines([CGPoint(x: m.x - 14, y: m.y - 8), CGPoint(x: m.x + 14, y: m.y - 8), CGPoint(x: m.x, y: m.y + 10)])
            p.closeSubpath()
            return [Stroke(path: p, filled: true)]
        case .frown:
            return [curve(CGPoint(x: m.x - 15, y: m.y + 7), CGPoint(x: m.x, y: m.y - 12), CGPoint(x: m.x + 15, y: m.y + 7))]
        case .flat:
            return [line([CGPoint(x: m.x - 11, y: m.y), CGPoint(x: m.x + 11, y: m.y)])]
        case .small:
            return [circle(m, 5.5, filled: false)]
        case .gasp:
            return [circle(CGPoint(x: m.x, y: m.y + 2), 11, filled: false)]
        case .kiss:
            var p = Path()
            p.move(to: CGPoint(x: m.x - 5, y: m.y - 11))
            p.addQuadCurve(to: CGPoint(x: m.x - 3, y: m.y), control: CGPoint(x: m.x + 10, y: m.y - 9))
            p.addQuadCurve(to: CGPoint(x: m.x - 5, y: m.y + 11), control: CGPoint(x: m.x + 10, y: m.y + 9))
            return [Stroke(path: p, filled: false)]
        case .squee:
            return [line([CGPoint(x: m.x - 12, y: m.y + 7), CGPoint(x: m.x, y: m.y - 7), CGPoint(x: m.x + 12, y: m.y + 7)])]
        case .grin:
            var p = Path()
            p.move(to: CGPoint(x: m.x - 17, y: m.y - 7))
            p.addLine(to: CGPoint(x: m.x + 17, y: m.y - 7))
            p.addQuadCurve(to: CGPoint(x: m.x - 17, y: m.y - 7), control: CGPoint(x: m.x, y: m.y + 22))
            p.closeSubpath()
            return [Stroke(path: p, filled: true)]
        case .wavy:
            var p = Path()
            p.move(to: CGPoint(x: m.x - 18, y: m.y))
            p.addQuadCurve(to: CGPoint(x: m.x - 6, y: m.y), control: CGPoint(x: m.x - 12, y: m.y - 9))
            p.addQuadCurve(to: CGPoint(x: m.x + 6, y: m.y), control: CGPoint(x: m.x, y: m.y + 9))
            p.addQuadCurve(to: CGPoint(x: m.x + 18, y: m.y), control: CGPoint(x: m.x + 12, y: m.y - 9))
            return [Stroke(path: p, filled: false)]
        case .teeth:
            var p = Path(roundedRect: CGRect(x: m.x - 16, y: m.y - 8, width: 32, height: 16), cornerRadius: 4)
            p.move(to: CGPoint(x: m.x - 16, y: m.y))
            p.addLine(to: CGPoint(x: m.x + 16, y: m.y))
            for x in [m.x - 6, m.x + 6] {
                p.move(to: CGPoint(x: x, y: m.y - 8))
                p.addLine(to: CGPoint(x: x, y: m.y + 8))
            }
            return [Stroke(path: p, filled: false)]
        case .square:
            return [Stroke(path: Path(roundedRect: CGRect(x: m.x - 12, y: m.y - 9, width: 24, height: 19), cornerRadius: 4),
                           filled: false)]
        case .tongue:
            return [curve(CGPoint(x: m.x - 14, y: m.y - 6), CGPoint(x: m.x, y: m.y + 10), CGPoint(x: m.x + 14, y: m.y - 6)),
                    circle(CGPoint(x: m.x + 5, y: m.y + 7), 5.5, filled: true)]
        case .rage:
            var p = Path()
            p.addLines([CGPoint(x: m.x - 13, y: m.y + 8), CGPoint(x: m.x + 13, y: m.y + 8), CGPoint(x: m.x, y: m.y - 9)])
            p.closeSubpath()
            return [Stroke(path: p, filled: false)]
        case .meh:
            return [line([CGPoint(x: m.x - 12, y: m.y + 3), CGPoint(x: m.x + 12, y: m.y - 3)])]
        }
    }

    /// A little "z" for a sleeping face.
    private static func zee(at c: CGPoint, size: CGFloat) -> Stroke {
        let a = CGPoint(x: c.x, y: c.y)
        let b = CGPoint(x: c.x + size, y: c.y)
        let d = CGPoint(x: c.x, y: c.y + size)
        let e = CGPoint(x: c.x + size, y: c.y + size)
        return line([a, b, d, e])
    }

    private static func extra(_ extra: Extra) -> [Stroke] {
        switch extra {
        case .none:
            return []
        case .blush:
            var marks: [Stroke] = []
            for c in [left, right] {
                for dx: CGFloat in [-9, 0, 9] {
                    let bottom = CGPoint(x: c.x + dx - 3, y: c.y + 30)
                    let top = CGPoint(x: c.x + dx + 3, y: c.y + 22)
                    marks.append(line([bottom, top]))
                }
            }
            return marks
        case .tears:
            return [left, right].map { c in
                var p = Path()
                let top = CGPoint(x: c.x + 3, y: c.y + 16)
                p.move(to: top)
                p.addQuadCurve(to: CGPoint(x: c.x + 3, y: c.y + 38), control: CGPoint(x: c.x - 9, y: c.y + 34))
                p.addQuadCurve(to: top, control: CGPoint(x: c.x + 15, y: c.y + 34))
                return Stroke(path: p, filled: true)
            }
        case .sweat:
            var p = Path()
            let top = CGPoint(x: 178, y: 6)
            p.move(to: top)
            p.addQuadCurve(to: CGPoint(x: 178, y: 30), control: CGPoint(x: 165, y: 26))
            p.addQuadCurve(to: top, control: CGPoint(x: 191, y: 26))
            return [Stroke(path: p, filled: false)]
        case .anger:
            let c = CGPoint(x: 182, y: 14)
            return [
                curve(CGPoint(x: c.x - 11, y: c.y - 4), CGPoint(x: c.x - 4, y: c.y - 4), CGPoint(x: c.x - 4, y: c.y - 11)),
                curve(CGPoint(x: c.x + 4, y: c.y - 11), CGPoint(x: c.x + 4, y: c.y - 4), CGPoint(x: c.x + 11, y: c.y - 4)),
                curve(CGPoint(x: c.x + 11, y: c.y + 4), CGPoint(x: c.x + 4, y: c.y + 4), CGPoint(x: c.x + 4, y: c.y + 11)),
                curve(CGPoint(x: c.x - 4, y: c.y + 11), CGPoint(x: c.x - 4, y: c.y + 4), CGPoint(x: c.x - 11, y: c.y + 4)),
            ]
        case .sparkles:
            return [CGPoint(x: 14, y: 16), CGPoint(x: 186, y: 82)].map { c in
                var p = Path()
                for i in 0..<8 {
                    let r: CGFloat = i % 2 == 0 ? 10 : 2.5
                    let angle = CGFloat(i) * .pi / 4 - .pi / 2
                    let point = CGPoint(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r)
                    if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
                }
                p.closeSubpath()
                return Stroke(path: p, filled: true)
            }
        case .sleep:
            return [zee(at: CGPoint(x: 168, y: 18), size: 11), zee(at: CGPoint(x: 184, y: 2), size: 8)]
        }
    }
}

/// Draws a `Kaomoji`, scaled to fit, in one colour.
struct KaomojiView: View {
    let face: Kaomoji
    var color: Color = .white
    /// Line thickness in canvas units; thicker reads better when small.
    var lineWidth: CGFloat = Kaomoji.lineWidth

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / Kaomoji.canvas.width, size.height / Kaomoji.canvas.height)
            let drawn = CGSize(width: Kaomoji.canvas.width * scale, height: Kaomoji.canvas.height * scale)
            context.translateBy(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2)
            context.scaleBy(x: scale, y: scale)
            let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            for stroke in face.strokes {
                if stroke.filled {
                    context.fill(stroke.path, with: .color(color))
                } else {
                    context.stroke(stroke.path, with: .color(color), style: style)
                }
            }
        }
        .aspectRatio(Kaomoji.canvas.width / Kaomoji.canvas.height, contentMode: .fit)
    }
}

/// A face that's alive: blinks every few seconds and bobs a little. Still
/// when Reduce Motion is on.
struct LivelyKaomojiView: View {
    let face: Kaomoji
    var color: Color = .white

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blinking = false
    @State private var up = false

    private var shown: Kaomoji {
        guard blinking, ![.cross, .spiral, .heart, .star].contains(face.eyes) else { return face }
        var closed = face
        closed.eyes = .line
        return closed
    }

    var body: some View {
        KaomojiView(face: shown, color: color)
            .offset(y: up ? -2 : 1)
            .task(id: face) {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { up = true }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3.2))
                    blinking = true
                    try? await Task.sleep(for: .milliseconds(130))
                    blinking = false
                }
            }
    }
}
