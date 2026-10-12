import XCTest
@testable import RemindMe

/// The traced faces and the animation script.
final class FaceTests: XCTestCase {

    func testAll24FacesParseAndStayOnCanvas() {
        XCTAssertEqual(Face.allCases.count, 24)
        let canvas = CGRect(origin: .zero, size: FaceArt.canvas)
        for face in Face.allCases {
            let strokes = FaceShapes.strokes(face)
            XCTAssertFalse(strokes.isEmpty, "\(face) has no outline")
            let box = strokes.boundingBoxOfPath
            XCTAssertTrue(canvas.contains(box), "\(face) spills off the canvas: \(box)")
            XCTAssertGreaterThan(box.width, 60, "\(face) traced suspiciously small")
            if let tears = FaceShapes.tears(face) {
                XCTAssertTrue(canvas.contains(tears.boundingBoxOfPath), "\(face) tears off canvas")
            }
        }
    }

    func testOnlyTheCryingFacesHaveTears() {
        let withTears = Face.allCases.filter { FaceShapes.tears($0) != nil }
        XCTAssertEqual(Set(withTears), [.tearful, .wail])
    }

    func testLogoParses() {
        let box = FaceShapes.logo.boundingBoxOfPath
        XCTAssertGreaterThan(box.width, 100)
        XCTAssertGreaterThan(box.width / box.height, 4, "the —ω— logo is wide and short")
    }

    func testParserHandlesNegativeAndDecimalNumbers() {
        let path = SVGPathParser.cgPath(from: "M-1.5 2L10 2.25C10 5 5 8 -1.5 8Z")
        let box = path.boundingBoxOfPath
        XCTAssertEqual(box.minX, -1.5, accuracy: 0.001)
        XCTAssertEqual(box.minY, 2, accuracy: 0.001)
        XCTAssertEqual(box.maxX, 10, accuracy: 0.001)
    }

    // MARK: - Mood follows the nagging

    func testMoodRisesWithEachPop() {
        XCTAssertEqual(FaceMood.forPop(count: 1, maxPops: 3), .gentle)
        XCTAssertEqual(FaceMood.forPop(count: 2, maxPops: 3), .nudge)
        XCTAssertEqual(FaceMood.forPop(count: 3, maxPops: 3), .urgent)
        XCTAssertEqual(FaceMood.forPop(count: 2, maxPops: 2), .urgent, "last pop is always urgent")
        XCTAssertEqual(FaceMood.forPop(count: 1, maxPops: 1), .gentle, "a single pop stays friendly")
        XCTAssertEqual(FaceMood.forPop(count: 5, maxPops: 10), .nudge)
    }

    func testEveryOneOfThe24FacesIsUsed() {
        let moods: [FaceMood] = [.gentle, .nudge, .urgent, .done, .snoozed, .skipped]
        let used = Set(moods.flatMap { FaceScript.beats(for: $0).map { $0.face } })
        XCTAssertEqual(used, Set(Face.allCases), "unused: \(Set(Face.allCases).subtracting(used))")
    }

    // MARK: - Script timing

    func testGentleBlinksByClosingItsEyes() {
        XCTAssertEqual(FaceScript.face(for: .gentle, at: 0), .owo)
        XCTAssertEqual(FaceScript.face(for: .gentle, at: 2.25), .sleepy, "blink = same face, eyes shut")
        XCTAssertEqual(FaceScript.face(for: .gentle, at: 2.5), .owo)
    }

    func testPopMoodsLoopForever() {
        let total = FaceScript.beats(for: .urgent).reduce(0) { $0 + $1.duration }
        XCTAssertEqual(FaceScript.face(for: .urgent, at: 0.1), FaceScript.face(for: .urgent, at: total * 7 + 0.1))
    }

    func testReactionsPlayOnceThenHold() {
        XCTAssertEqual(FaceScript.face(for: .done, at: 0), .happy)
        XCTAssertEqual(FaceScript.face(for: .done, at: 0.3), .squee)
        XCTAssertEqual(FaceScript.face(for: .done, at: 60), .happy)
        XCTAssertEqual(FaceScript.face(for: .snoozed, at: 60), .sleepy)
        XCTAssertEqual(FaceScript.face(for: .skipped, at: 60), .sob)
    }

    func testReactionFinishesBeforeThePanelCloses() {
        // The card waits `reactionDuration` before running the action; the
        // reaction's non-held beats should have played by then.
        let wait = Double(LiveReminderView.reactionDuration.components.attoseconds) / 1e18
            + Double(LiveReminderView.reactionDuration.components.seconds)
        for mood in [FaceMood.done, .snoozed, .skipped] {
            let played = FaceScript.beats(for: mood).dropLast().reduce(0) { $0 + $1.duration }
            XCTAssertLessThanOrEqual(played, wait, "\(mood) reaction is cut off")
        }
    }

    func testEveryMoodFitsTheFaceWindow() {
        for mood in FaceMood.allCases {
            let span = FaceLayout.verticalSpan(of: mood)
            let heightPt = (span.upperBound - span.lowerBound) * FaceLayout.scale
            XCTAssertLessThanOrEqual(heightPt, FaceLayout.windowHeight + 3, "\(mood) is too tall for the card")
            // Centred: the span's middle lands on the window's middle.
            let middle = (span.lowerBound + span.upperBound) / 2 * FaceLayout.scale + FaceLayout.offset(for: mood)
            XCTAssertEqual(middle, FaceLayout.windowHeight / 2, accuracy: 0.01)
        }
    }

    func testReduceMotionKeepsFacesStill() {
        for mood in [FaceMood.gentle, .nudge, .urgent, .done, .snoozed, .skipped] {
            for t in stride(from: 0.0, through: 3.0, by: 0.37) {
                let f = FaceScript.frame(for: mood, at: t, reduceMotion: true)
                XCTAssertEqual(f.dx, 0); XCTAssertEqual(f.dy, 0); XCTAssertEqual(f.rotation, 0)
                XCTAssertEqual(f.scaleX, 1); XCTAssertEqual(f.scaleY, 1)
            }
        }
    }

    func testMotionStaysSmall() {
        // Nothing should fly out of its frame.
        for mood in [FaceMood.gentle, .nudge, .urgent, .done, .snoozed, .skipped] {
            for t in stride(from: 0.0, through: 6.0, by: 0.01) {
                let f = FaceScript.frame(for: mood, at: t)
                XCTAssertLessThanOrEqual(abs(f.dx), 5); XCTAssertLessThanOrEqual(abs(f.dy), 11)
                XCTAssertLessThanOrEqual(abs(f.rotation), 6)
                XCTAssertTrue((0.9...1.1).contains(f.scaleX) && (0.9...1.1).contains(f.scaleY))
            }
        }
    }
}
