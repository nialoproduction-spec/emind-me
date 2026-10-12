import XCTest
@testable import RemindMe

/// When the floating panel fades itself out.
final class PanelAutoHideTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    // MARK: - The pill (time + next reminder)

    func testPillStaysForItsPeekThenGoes() {
        // Shown at t0, never touched.
        XCTAssertFalse(PanelAutoHide.shouldHide(now: at(5.9), shownAt: t0, lastEngaged: t0, isExpanded: false))
        XCTAssertTrue(PanelAutoHide.shouldHide(now: at(6), shownAt: t0, lastEngaged: t0, isExpanded: false))
    }

    func testHoveringKeepsThePillUp() {
        // Pointer rested on it until t=10 (the watch keeps bumping lastEngaged).
        XCTAssertFalse(PanelAutoHide.shouldHide(now: at(10), shownAt: t0, lastEngaged: at(10), isExpanded: false))
        // Pointer left at 10: goes after the short grace, not another full peek.
        XCTAssertFalse(PanelAutoHide.shouldHide(now: at(11.9), shownAt: t0, lastEngaged: at(10), isExpanded: false))
        XCTAssertTrue(PanelAutoHide.shouldHide(now: at(12), shownAt: t0, lastEngaged: at(10), isExpanded: false))
    }

    func testBriefHoverEarlyDoesNotCutThePeekShort() {
        // Pointer passed over at t=1; the pill still gets its full peek.
        XCTAssertFalse(PanelAutoHide.shouldHide(now: at(4), shownAt: t0, lastEngaged: at(1), isExpanded: false))
        XCTAssertTrue(PanelAutoHide.shouldHide(now: at(6), shownAt: t0, lastEngaged: at(1), isExpanded: false))
    }

    // MARK: - The expanded list

    func testExpandedListStaysWhileInUse() {
        // Typing or pointing at t=30 keeps it open well past the pill's peek.
        XCTAssertFalse(PanelAutoHide.shouldHide(now: at(44), shownAt: t0, lastEngaged: at(30), isExpanded: true))
    }

    func testExpandedListGoesAfterAQuietSpell() {
        XCTAssertFalse(PanelAutoHide.shouldHide(now: at(14.9), shownAt: t0, lastEngaged: t0, isExpanded: true))
        XCTAssertTrue(PanelAutoHide.shouldHide(now: at(15), shownAt: t0, lastEngaged: t0, isExpanded: true))
    }

    func testTimingsAreNotificationLike() {
        XCTAssertTrue((3...10).contains(PanelAutoHide.peekDuration), "a few seconds, like a notification")
        XCTAssertLessThan(PanelAutoHide.fadeIn, 0.5)
        XCTAssertLessThan(PanelAutoHide.fadeOut, 0.5)
    }
}
