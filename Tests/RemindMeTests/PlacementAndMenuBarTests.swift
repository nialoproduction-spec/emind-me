import XCTest
import AppKit
@testable import RemindMe

/// Where the panel goes for each placement setting.
final class PlacementTests: XCTestCase {
    /// A 1440 × 900 screen with a 25pt menu bar.
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
    private let card = CGSize(width: 280, height: 204)

    private func frame(_ placement: PanelPlacement, size: CGSize? = nil,
                       custom: CGPoint? = nil, icon: CGRect? = nil) -> CGRect {
        PanelPlacementMath.frame(for: placement, size: size ?? card, visibleFrame: screen,
                                 customTopLeft: custom, statusItemFrame: icon)
    }

    func testDefaultIsTopRight() {
        XCTAssertEqual(PlacementSettings.default.placement, .topRight)
    }

    func testCorners() {
        XCTAssertEqual(frame(.topRight).origin, CGPoint(x: 1148, y: 659))
        XCTAssertEqual(frame(.topLeft).origin, CGPoint(x: 12, y: 659))
        XCTAssertEqual(frame(.bottomRight).origin, CGPoint(x: 1148, y: 12))
        XCTAssertEqual(frame(.bottomLeft).origin, CGPoint(x: 12, y: 12))
    }

    func testCustomSpotIsWhereItWasDragged() {
        let f = frame(.custom, custom: CGPoint(x: 300, y: 700))
        XCTAssertEqual(f.minX, 300)
        XCTAssertEqual(f.maxY, 700, "the dragged top-left corner stays put")
    }

    func testCustomWithoutADragFallsBackToTopRight() {
        XCTAssertEqual(frame(.custom), frame(.topRight))
    }

    func testCustomSpotOffScreenIsPulledBackOn() {
        let f = frame(.custom, custom: CGPoint(x: 5000, y: 5000))
        XCTAssertTrue(screen.contains(f))
    }

    func testMenuBarModeSitsCentredUnderTheIcon() {
        let icon = CGRect(x: 1000, y: 875, width: 38, height: 25)
        let f = frame(.menuBar, icon: icon)
        XCTAssertEqual(f.midX, icon.midX, accuracy: 0.01)
        XCTAssertEqual(f.maxY, icon.minY - PanelPlacementMath.menuBarGap, accuracy: 0.01)
        XCTAssertTrue(screen.contains(f))
    }

    func testMenuBarModeNearTheScreenEdgeStaysOnScreen() {
        let f = frame(.menuBar, icon: CGRect(x: 1420, y: 875, width: 38, height: 25))
        XCTAssertTrue(screen.contains(f))
    }

    func testMenuBarModeWithoutAnIconFallsBackToTopRight() {
        XCTAssertEqual(frame(.menuBar), frame(.topRight))
    }

    func testResizingKeepsTheChosenCornerAnchored() {
        let small = CGSize(width: 220, height: 56), big = CGSize(width: 320, height: 420)
        XCTAssertEqual(frame(.topRight, size: small).maxX, frame(.topRight, size: big).maxX)
        XCTAssertEqual(frame(.topRight, size: small).maxY, frame(.topRight, size: big).maxY)
        XCTAssertEqual(frame(.bottomLeft, size: small).minX, frame(.bottomLeft, size: big).minX)
        XCTAssertEqual(frame(.bottomLeft, size: small).minY, frame(.bottomLeft, size: big).minY)
        XCTAssertEqual(frame(.bottomRight, size: small).maxX, frame(.bottomRight, size: big).maxX)
        XCTAssertEqual(frame(.bottomRight, size: small).minY, frame(.bottomRight, size: big).minY)
        let icon = CGRect(x: 700, y: 875, width: 38, height: 25)
        XCTAssertEqual(frame(.menuBar, size: small, icon: icon).midX, frame(.menuBar, size: big, icon: icon).midX, accuracy: 0.01)
    }

    func testEveryPlacementHasALabel() {
        for placement in PanelPlacement.allCases { XCTAssertFalse(placement.label.isEmpty) }
    }
}

/// The animated menu bar icon.
final class MenuBarFaceTests: XCTestCase {

    func testEveryFrameIsTheSameSizeSoTheMenuBarNeverShifts() {
        let logo = MenuBarFace.logoImage()
        XCTAssertEqual(logo.size, MenuBarFace.imageSize)
        XCTAssertTrue(logo.isTemplate, "template images follow light / dark menu bars")
        for reaction in HoverReaction.allCases {
            let span = MenuBarFace.span(of: reaction.beats.map { $0.face })
            for beat in reaction.beats {
                let image = MenuBarFace.faceImage(beat.face, span: span, offset: .zero)
                XCTAssertEqual(image.size, MenuBarFace.imageSize)
                XCTAssertTrue(image.isTemplate)
            }
        }
    }

    func testHoverReactionIsRandomButNeverTheSameTwiceInARow() {
        var seen = Set<HoverReaction>()
        var previous: HoverReaction?
        for _ in 0..<200 {
            let next = HoverReaction.random(excluding: previous)
            XCTAssertNotEqual(next, previous)
            seen.insert(next)
            previous = next
        }
        XCTAssertGreaterThan(seen.count, 4, "plenty of variety")
    }

    func testReactionsAreShortAndHoldTheirLastFace() {
        for reaction in HoverReaction.allCases {
            XCTAssertFalse(reaction.beats.isEmpty)
            XCTAssertLessThanOrEqual(reaction.duration, 1.6, "\(reaction) should be a quick reaction")
            XCTAssertEqual(reaction.face(at: 60), reaction.beats.last!.face)
        }
    }

    func testIncludesTheMoodsAskedFor() {
        let names = Set(HoverReaction.allCases.map(\.rawValue))
        XCTAssertTrue(names.isSuperset(of: ["happy", "scared", "shocked"]))
    }

    func testMotionIsTiny() {
        for reaction in HoverReaction.allCases {
            for t in stride(from: 0.0, through: 2.0, by: 0.01) {
                let m = reaction.motion(at: t)
                XCTAssertLessThanOrEqual(abs(m.x), 2.5); XCTAssertLessThanOrEqual(abs(m.y), 2.5)
            }
        }
    }
}
