import SwiftUI

/// Cute faces built from parts, kaomoji style: (｡•ᴗ•｡) (๑>◡<๑) (˶ᵔ ᵕ ᵔ˶)♡.
/// What makes them cute, and what this follows: eyes set close together,
/// tiny soft mouths (ω ᴗ ᵕ ‿), round shiny or closed-arc eyes, and blush,
/// sparkles, hearts and flowers. Nothing harsh: no screams, fangs, spirals or
/// glasses. Drawn in the same white line style as the traced faces, on a
/// 200 × 104 canvas. 22 eyes × 23 mouths × 15 extras = 7,590 faces.
struct Kaomoji: Hashable {
    enum Eyes: Int, CaseIterable {
        case dot, bead, shiny, pleading, happy, content, caret, squint, star, heart,
             wink, line, relaxed, crying, worried, determined, twinkle, ring, tinyRing,
             cross, lashes, doubleLine
    }

    enum Mouth: Int, CaseIterable {
        case cat, smile, tiny, wide, open, grin, laugh, small, gasp, kiss, pucker, squee,
             tongue, wavy, frown, tinyFrown, flat, shout, cackle, smirk, whistle, tongueOut, openOutline
    }

    enum Extra: Int, CaseIterable {
        case none, blush, cheeks, sparkles, hearts, flower, music, sleep, sweat, tears,
             anger, question, exclaim, bubble, huff
    }

    enum Mood: CaseIterable {
        case happy, calm, love, shy, sad, angry, shocked, silly, pleading, nervous, dead
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
        .happy: ([.dot, .bead, .shiny, .happy, .caret, .squint, .star, .wink, .relaxed, .twinkle],
                 [.cat, .smile, .tiny, .wide, .open, .grin, .laugh, .squee, .tongue, .cackle],
                 [.none, .none, .blush, .cheeks, .sparkles, .flower, .music]),
        .calm: ([.content, .relaxed, .line, .doubleLine, .bead, .lashes],
                [.cat, .tiny, .smile, .flat, .whistle],
                [.none, .sleep, .bubble, .cheeks, .music]),
        .love: ([.heart, .shiny, .happy, .star, .lashes, .twinkle],
                [.smile, .kiss, .pucker, .cat, .open, .tiny],
                [.hearts, .blush, .cheeks, .sparkles, .flower]),
        .shy: ([.content, .relaxed, .dot, .bead, .lashes],
               [.tiny, .smile, .wavy, .pucker, .cat],
               [.blush, .blush, .cheeks, .hearts]),
        .sad: ([.crying, .worried, .pleading, .relaxed],
               [.frown, .tinyFrown, .wavy, .flat, .tiny],
               [.tears, .tears, .none, .sweat]),
        .angry: ([.determined, .squint, .line],
                 [.frown, .shout, .flat, .tinyFrown, .cat],
                 [.anger, .anger, .huff, .none]),
        .shocked: ([.ring, .tinyRing, .dot, .shiny],
                   [.gasp, .small, .wavy, .openOutline, .shout],
                   [.exclaim, .sweat, .none, .question]),
        .silly: ([.squint, .wink, .dot, .twinkle, .star, .happy],
                 [.tongueOut, .tongue, .cackle, .squee, .laugh, .smirk, .whistle],
                 [.none, .question, .sweat, .music, .sparkles]),
        .pleading: ([.pleading, .shiny, .tinyRing, .worried],
                    [.tinyFrown, .tiny, .pucker, .wavy, .small],
                    [.cheeks, .tears, .blush, .none, .sparkles]),
        .nervous: ([.worried, .tinyRing, .dot, .ring],
                   [.wavy, .flat, .tiny, .small, .openOutline],
                   [.sweat, .sweat, .question, .exclaim]),
        .dead: ([.cross, .crying],
                [.wavy, .flat, .tinyFrown, .gasp, .tongueOut],
                [.none, .sweat, .tears]),
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
    /// The part of the canvas a face actually uses (it's drawn close
    /// together), so it fills its frame instead of floating in the middle.
    static let viewBox = CGRect(x: 26, y: 0, width: 148, height: 104)
    static let lineWidth: CGFloat = 4.5

    struct Stroke {
        var path: Path
        var filled: Bool
        /// Filled with holes (a shine in an eye, a tongue in a mouth).
        var evenOdd = false
    }

    // Eyes close together, the mouth just below: that's most of the cuteness.
    private static let left = CGPoint(x: 70, y: 44)
    private static let right = CGPoint(x: 130, y: 44)
    private static let mouthCentre = CGPoint(x: 100, y: 60)

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

    private static func starPath(at c: CGPoint, points: Int, outer: CGFloat, inner: CGFloat) -> Path {
        var p = Path()
        for i in 0..<(points * 2) {
            let r = i % 2 == 0 ? outer : inner
            let angle = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
            let point = CGPoint(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r)
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        p.closeSubpath()
        return p
    }

    /// `side`: -1 for the left eye, +1 for the right, so slanted parts mirror.
    private static func eye(_ eyes: Eyes, at c: CGPoint, side: CGFloat) -> [Stroke] {
        let inner = -side // toward the middle of the face
        switch eyes {
        case .dot:
            return [circle(c, 8, filled: true)]
        case .bead:
            return [circle(CGPoint(x: c.x, y: c.y + 2), 5, filled: true)]
        case .shiny:
            var p = Path(ellipseIn: CGRect(x: c.x - 10, y: c.y - 10, width: 20, height: 20))
            p.addEllipse(in: CGRect(x: c.x - 0.5, y: c.y - 7.5, width: 7, height: 7))
            p.addEllipse(in: CGRect(x: c.x - 6, y: c.y + 2.5, width: 3.2, height: 3.2))
            return [Stroke(path: p, filled: true, evenOdd: true)]
        case .pleading:
            var p = Path(ellipseIn: CGRect(x: c.x - 11.5, y: c.y - 11, width: 23, height: 23))
            p.addEllipse(in: CGRect(x: c.x - 8, y: c.y - 8, width: 9, height: 9))
            p.addEllipse(in: CGRect(x: c.x + 2, y: c.y + 2.5, width: 4.4, height: 4.4))
            return [Stroke(path: p, filled: true, evenOdd: true)]
        case .happy:
            return [curve(CGPoint(x: c.x - 11, y: c.y + 5), CGPoint(x: c.x, y: c.y - 12), CGPoint(x: c.x + 11, y: c.y + 5))]
        case .content:
            return [curve(CGPoint(x: c.x - 11, y: c.y - 3), CGPoint(x: c.x, y: c.y + 11), CGPoint(x: c.x + 11, y: c.y - 3))]
        case .relaxed:
            return [curve(CGPoint(x: c.x - 8, y: c.y), CGPoint(x: c.x, y: c.y + 7), CGPoint(x: c.x + 8, y: c.y))]
        case .caret:
            return [line([CGPoint(x: c.x - 9, y: c.y + 5), CGPoint(x: c.x, y: c.y - 6), CGPoint(x: c.x + 9, y: c.y + 5)])]
        case .squint:
            // ">" on the left, "<" on the right.
            return [line([CGPoint(x: c.x - 8 * inner, y: c.y - 8), CGPoint(x: c.x + 8 * inner, y: c.y),
                          CGPoint(x: c.x - 8 * inner, y: c.y + 8)])]
        case .star:
            return [Stroke(path: starPath(at: c, points: 5, outer: 10, inner: 4.3), filled: true)]
        case .heart:
            return [heart(at: CGPoint(x: c.x, y: c.y + 1), size: 9)]
        case .wink:
            return [circle(c, 8, filled: true)]
        case .line:
            return [line([CGPoint(x: c.x - 10, y: c.y), CGPoint(x: c.x + 10, y: c.y)])]
        case .crying:
            return [line([CGPoint(x: c.x - 10, y: c.y - 6), CGPoint(x: c.x + 10, y: c.y - 6)]),
                    line([CGPoint(x: c.x, y: c.y - 6), CGPoint(x: c.x, y: c.y + 9)])]
        case .worried:
            return [circle(CGPoint(x: c.x, y: c.y + 3), 5.5, filled: true),
                    line([CGPoint(x: c.x - 10 * inner, y: c.y - 6), CGPoint(x: c.x + 8 * inner, y: c.y - 13)])]
        case .determined:
            return [circle(CGPoint(x: c.x, y: c.y + 3), 6, filled: true),
                    line([CGPoint(x: c.x - 10 * inner, y: c.y - 13), CGPoint(x: c.x + 8 * inner, y: c.y - 7)])]
        case .twinkle:
            return [Stroke(path: starPath(at: c, points: 4, outer: 10, inner: 3.2), filled: false)]
        case .ring:
            return [circle(c, 8, filled: false), circle(c, 3, filled: true)]
        case .tinyRing:
            return [circle(CGPoint(x: c.x, y: c.y + 2), 4.5, filled: false)]
        case .cross:
            return [line([CGPoint(x: c.x - 7, y: c.y - 7), CGPoint(x: c.x + 7, y: c.y + 7)]),
                    line([CGPoint(x: c.x + 7, y: c.y - 7), CGPoint(x: c.x - 7, y: c.y + 7)])]
        case .lashes:
            return [curve(CGPoint(x: c.x - 10, y: c.y - 2), CGPoint(x: c.x, y: c.y + 10), CGPoint(x: c.x + 10, y: c.y - 2)),
                    line([CGPoint(x: c.x + 10 * side, y: c.y - 2), CGPoint(x: c.x + 15 * side, y: c.y - 7)])]
        case .doubleLine:
            return [line([CGPoint(x: c.x - 9, y: c.y - 3.5), CGPoint(x: c.x + 9, y: c.y - 3.5)]),
                    line([CGPoint(x: c.x - 9, y: c.y + 3.5), CGPoint(x: c.x + 9, y: c.y + 3.5)])]
        }
    }

    private static func mouth(_ mouth: Mouth) -> [Stroke] {
        let m = mouthCentre
        switch mouth {
        case .cat:
            return [curve(CGPoint(x: m.x - 11, y: m.y - 3), CGPoint(x: m.x - 5.5, y: m.y + 8), CGPoint(x: m.x, y: m.y - 1)),
                    curve(CGPoint(x: m.x, y: m.y - 1), CGPoint(x: m.x + 5.5, y: m.y + 8), CGPoint(x: m.x + 11, y: m.y - 3))]
        case .smile:
            return [curve(CGPoint(x: m.x - 8, y: m.y - 3), CGPoint(x: m.x, y: m.y + 8), CGPoint(x: m.x + 8, y: m.y - 3))]
        case .tiny:
            return [curve(CGPoint(x: m.x - 5, y: m.y - 1), CGPoint(x: m.x, y: m.y + 5), CGPoint(x: m.x + 5, y: m.y - 1))]
        case .wide:
            return [curve(CGPoint(x: m.x - 13, y: m.y - 3), CGPoint(x: m.x, y: m.y + 6), CGPoint(x: m.x + 13, y: m.y - 3))]
        case .open:
            var p = Path()
            p.addLines([CGPoint(x: m.x - 8, y: m.y - 4), CGPoint(x: m.x + 8, y: m.y - 4), CGPoint(x: m.x, y: m.y + 6)])
            p.closeSubpath()
            return [Stroke(path: p, filled: true)]
        case .grin:
            var p = Path()
            p.move(to: CGPoint(x: m.x - 10, y: m.y - 4))
            p.addLine(to: CGPoint(x: m.x + 10, y: m.y - 4))
            p.addQuadCurve(to: CGPoint(x: m.x - 10, y: m.y - 4), control: CGPoint(x: m.x, y: m.y + 14))
            p.closeSubpath()
            return [Stroke(path: p, filled: true)]
        case .laugh:
            var p = Path()
            p.move(to: CGPoint(x: m.x - 11, y: m.y - 4))
            p.addLine(to: CGPoint(x: m.x + 11, y: m.y - 4))
            p.addQuadCurve(to: CGPoint(x: m.x - 11, y: m.y - 4), control: CGPoint(x: m.x, y: m.y + 16))
            p.closeSubpath()
            p.addEllipse(in: CGRect(x: m.x - 4.5, y: m.y + 1, width: 9, height: 5))
            return [Stroke(path: p, filled: true, evenOdd: true)]
        case .small:
            return [circle(CGPoint(x: m.x, y: m.y + 1), 3.5, filled: false)]
        case .gasp:
            return [circle(CGPoint(x: m.x, y: m.y + 2), 6, filled: false)]
        case .kiss:
            var p = Path()
            p.move(to: CGPoint(x: m.x - 3, y: m.y - 7))
            p.addQuadCurve(to: CGPoint(x: m.x - 2, y: m.y), control: CGPoint(x: m.x + 7, y: m.y - 6))
            p.addQuadCurve(to: CGPoint(x: m.x - 3, y: m.y + 7), control: CGPoint(x: m.x + 7, y: m.y + 6))
            return [Stroke(path: p, filled: false)]
        case .pucker:
            var p = Path()
            p.move(to: CGPoint(x: m.x + 3, y: m.y - 7))
            p.addQuadCurve(to: CGPoint(x: m.x + 2, y: m.y), control: CGPoint(x: m.x - 7, y: m.y - 6))
            p.addQuadCurve(to: CGPoint(x: m.x + 3, y: m.y + 7), control: CGPoint(x: m.x - 7, y: m.y + 6))
            return [Stroke(path: p, filled: false)]
        case .squee:
            return [line([CGPoint(x: m.x - 8, y: m.y + 5), CGPoint(x: m.x, y: m.y - 5), CGPoint(x: m.x + 8, y: m.y + 5)])]
        case .tongue:
            return [curve(CGPoint(x: m.x - 9, y: m.y - 3), CGPoint(x: m.x, y: m.y + 7), CGPoint(x: m.x + 9, y: m.y - 3)),
                    circle(CGPoint(x: m.x + 3, y: m.y + 4), 3.5, filled: true)]
        case .wavy:
            var p = Path()
            p.move(to: CGPoint(x: m.x - 11, y: m.y))
            p.addQuadCurve(to: CGPoint(x: m.x - 4, y: m.y), control: CGPoint(x: m.x - 7.5, y: m.y - 5))
            p.addQuadCurve(to: CGPoint(x: m.x + 4, y: m.y), control: CGPoint(x: m.x, y: m.y + 5))
            p.addQuadCurve(to: CGPoint(x: m.x + 11, y: m.y), control: CGPoint(x: m.x + 7.5, y: m.y - 5))
            return [Stroke(path: p, filled: false)]
        case .frown:
            return [curve(CGPoint(x: m.x - 9, y: m.y + 4), CGPoint(x: m.x, y: m.y - 7), CGPoint(x: m.x + 9, y: m.y + 4))]
        case .tinyFrown:
            return [curve(CGPoint(x: m.x - 5, y: m.y + 2), CGPoint(x: m.x, y: m.y - 5), CGPoint(x: m.x + 5, y: m.y + 2))]
        case .flat:
            return [line([CGPoint(x: m.x - 6, y: m.y), CGPoint(x: m.x + 6, y: m.y)])]
        case .shout:
            return [Stroke(path: Path(roundedRect: CGRect(x: m.x - 6, y: m.y - 5, width: 12, height: 10), cornerRadius: 2.5),
                           filled: false)]
        case .cackle:
            var p = Path()
            p.addLines([CGPoint(x: m.x - 7, y: m.y - 6), CGPoint(x: m.x, y: m.y + 7), CGPoint(x: m.x + 7, y: m.y - 6)])
            p.move(to: CGPoint(x: m.x - 3.5, y: m.y))
            p.addLine(to: CGPoint(x: m.x + 3.5, y: m.y))
            return [Stroke(path: p, filled: false)]
        case .smirk:
            return [curve(CGPoint(x: m.x - 8, y: m.y + 1), CGPoint(x: m.x + 3, y: m.y + 5), CGPoint(x: m.x + 10, y: m.y - 5))]
        case .whistle:
            return [circle(CGPoint(x: m.x + 5, y: m.y), 3, filled: false)]
        case .tongueOut:
            return [curve(CGPoint(x: m.x - 10, y: m.y - 3), CGPoint(x: m.x, y: m.y + 5), CGPoint(x: m.x + 10, y: m.y - 3)),
                    Stroke(path: Path(roundedRect: CGRect(x: m.x - 4, y: m.y + 1, width: 8, height: 10), cornerRadius: 4),
                           filled: true)]
        case .openOutline:
            var p = Path()
            p.addLines([CGPoint(x: m.x - 7, y: m.y - 4), CGPoint(x: m.x + 7, y: m.y - 4), CGPoint(x: m.x, y: m.y + 5)])
            p.closeSubpath()
            return [Stroke(path: p, filled: false)]
        }
    }

    private static func extra(_ extra: Extra) -> [Stroke] {
        switch extra {
        case .none:
            return []
        case .blush:
            var marks: [Stroke] = []
            for c in [left, right] {
                for dx: CGFloat in [-6, 0, 6] {
                    let bottom = CGPoint(x: c.x + dx - 2, y: c.y + 21)
                    let top = CGPoint(x: c.x + dx + 2, y: c.y + 15)
                    marks.append(line([bottom, top]))
                }
            }
            return marks
        case .cheeks:
            // Like the ๑ in (๑•ᴗ•๑): little round cheeks just outside the eyes.
            return [left, right].map { c in
                let side: CGFloat = c.x < 100 ? -1 : 1
                return Stroke(path: Path(ellipseIn: CGRect(x: c.x + 19 * side - 5, y: c.y + 8, width: 10, height: 6.5)),
                              filled: true)
            }
        case .sparkles:
            return [Stroke(path: starPath(at: CGPoint(x: 40, y: 22), points: 4, outer: 8, inner: 2), filled: true),
                    Stroke(path: starPath(at: CGPoint(x: 160, y: 72), points: 4, outer: 6, inner: 1.6), filled: true)]
        case .hearts:
            return [heart(at: CGPoint(x: 160, y: 22), size: 7), heart(at: CGPoint(x: 171, y: 38), size: 4.5)]
        case .flower:
            var petals = Path()
            let c = CGPoint(x: 160, y: 20)
            for i in 0..<5 {
                let angle = CGFloat(i) * 2 * .pi / 5 - .pi / 2
                let center = CGPoint(x: c.x + cos(angle) * 5.5, y: c.y + sin(angle) * 5.5)
                petals.addEllipse(in: CGRect(x: center.x - 3.6, y: center.y - 3.6, width: 7.2, height: 7.2))
            }
            return [Stroke(path: petals, filled: false), circle(c, 2.2, filled: true)]
        case .music:
            var p = Path()
            p.move(to: CGPoint(x: 166, y: 30))
            p.addLine(to: CGPoint(x: 166, y: 12))
            p.addQuadCurve(to: CGPoint(x: 173, y: 20), control: CGPoint(x: 173, y: 13))
            return [Stroke(path: p, filled: false),
                    Stroke(path: Path(ellipseIn: CGRect(x: 158, y: 26, width: 9, height: 7)), filled: true)]
        case .sleep:
            return [zee(at: CGPoint(x: 148, y: 18), size: 8), zee(at: CGPoint(x: 160, y: 6), size: 6)]
        case .sweat:
            var p = Path()
            let top = CGPoint(x: 156, y: 10)
            p.move(to: top)
            p.addQuadCurve(to: CGPoint(x: 156, y: 28), control: CGPoint(x: 147, y: 25))
            p.addQuadCurve(to: top, control: CGPoint(x: 165, y: 25))
            return [Stroke(path: p, filled: false)]
        case .tears:
            return [left, right].map { c in
                var p = Path()
                let top = CGPoint(x: c.x + 3, y: c.y + 9)
                p.move(to: top)
                p.addQuadCurve(to: CGPoint(x: c.x + 3, y: c.y + 24), control: CGPoint(x: c.x - 5, y: c.y + 21))
                p.addQuadCurve(to: top, control: CGPoint(x: c.x + 11, y: c.y + 21))
                return Stroke(path: p, filled: true)
            }
        case .anger:
            let c = CGPoint(x: 160, y: 16)
            return [
                curve(CGPoint(x: c.x - 7, y: c.y - 2.5), CGPoint(x: c.x - 2.5, y: c.y - 2.5), CGPoint(x: c.x - 2.5, y: c.y - 7)),
                curve(CGPoint(x: c.x + 2.5, y: c.y - 7), CGPoint(x: c.x + 2.5, y: c.y - 2.5), CGPoint(x: c.x + 7, y: c.y - 2.5)),
                curve(CGPoint(x: c.x + 7, y: c.y + 2.5), CGPoint(x: c.x + 2.5, y: c.y + 2.5), CGPoint(x: c.x + 2.5, y: c.y + 7)),
                curve(CGPoint(x: c.x - 2.5, y: c.y + 7), CGPoint(x: c.x - 2.5, y: c.y + 2.5), CGPoint(x: c.x - 7, y: c.y + 2.5)),
            ]
        case .question:
            var p = Path()
            p.move(to: CGPoint(x: 155, y: 13))
            p.addQuadCurve(to: CGPoint(x: 165, y: 11), control: CGPoint(x: 158, y: 4))
            p.addQuadCurve(to: CGPoint(x: 160, y: 23), control: CGPoint(x: 172, y: 18))
            p.addLine(to: CGPoint(x: 160, y: 25))
            return [Stroke(path: p, filled: false), circle(CGPoint(x: 160, y: 32), 2.5, filled: true)]
        case .exclaim:
            return [line([CGPoint(x: 160, y: 6), CGPoint(x: 160, y: 22)]), circle(CGPoint(x: 160, y: 29), 2.6, filled: true)]
        case .bubble:
            return [circle(CGPoint(x: 115, y: 54), 6, filled: false), circle(CGPoint(x: 113, y: 52), 1.5, filled: true)]
        case .huff:
            return [CGPoint(x: 40, y: 10), CGPoint(x: 160, y: 10)].map { c in
                var p = Path()
                p.move(to: CGPoint(x: c.x, y: c.y + 16))
                p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + 8), control: CGPoint(x: c.x - 5, y: c.y + 12))
                p.addQuadCurve(to: CGPoint(x: c.x, y: c.y), control: CGPoint(x: c.x + 5, y: c.y + 4))
                return Stroke(path: p, filled: false)
            }
        }
    }

    /// A small filled heart centred on `c`.
    private static func heart(at c: CGPoint, size s: CGFloat) -> Stroke {
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y + s))
        p.addCurve(to: CGPoint(x: c.x - s, y: c.y - s * 0.3), control1: CGPoint(x: c.x - s * 0.5, y: c.y + s * 0.5),
                   control2: CGPoint(x: c.x - s, y: c.y + s * 0.2))
        p.addCurve(to: CGPoint(x: c.x, y: c.y - s * 0.4), control1: CGPoint(x: c.x - s, y: c.y - s),
                   control2: CGPoint(x: c.x - s * 0.2, y: c.y - s))
        p.addCurve(to: CGPoint(x: c.x + s, y: c.y - s * 0.3), control1: CGPoint(x: c.x + s * 0.2, y: c.y - s),
                   control2: CGPoint(x: c.x + s, y: c.y - s))
        p.addCurve(to: CGPoint(x: c.x, y: c.y + s), control1: CGPoint(x: c.x + s, y: c.y + s * 0.2),
                   control2: CGPoint(x: c.x + s * 0.5, y: c.y + s * 0.5))
        p.closeSubpath()
        return Stroke(path: p, filled: true)
    }

    /// A little "z" for a sleeping face.
    private static func zee(at c: CGPoint, size: CGFloat) -> Stroke {
        let a = CGPoint(x: c.x, y: c.y)
        let b = CGPoint(x: c.x + size, y: c.y)
        let d = CGPoint(x: c.x, y: c.y + size)
        let e = CGPoint(x: c.x + size, y: c.y + size)
        return line([a, b, d, e])
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
            let box = Kaomoji.viewBox
            let scale = min(size.width / box.width, size.height / box.height)
            let drawn = CGSize(width: box.width * scale, height: box.height * scale)
            context.translateBy(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -box.minX, y: -box.minY)
            let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            for stroke in face.strokes {
                if stroke.filled {
                    context.fill(stroke.path, with: .color(color), style: FillStyle(eoFill: stroke.evenOdd))
                } else {
                    context.stroke(stroke.path, with: .color(color), style: style)
                }
            }
        }
        .aspectRatio(Kaomoji.viewBox.width / Kaomoji.viewBox.height, contentMode: .fit)
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
        guard blinking, [.dot, .bead, .shiny, .pleading, .ring, .tinyRing, .worried, .determined].contains(face.eyes)
        else { return face }
        var closed = face
        closed.eyes = .relaxed
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
