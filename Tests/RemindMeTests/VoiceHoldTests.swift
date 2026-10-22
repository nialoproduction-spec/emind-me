import XCTest
@testable import RemindMe

/// Holding Command alone starts listening; a quick tap or a Command shortcut
/// (⌘C, ⌘Z) never does. Pure logic, so no microphone or key events are needed.
final class VoiceHoldTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testQuickTapDoesNotStart() {
        var hold = CommandHold()
        XCTAssertNil(hold.modifiersChanged(commandOnly: true, at: t0))
        XCTAssertNil(hold.tick(at: t0.addingTimeInterval(0.1)))
        XCTAssertNil(hold.modifiersChanged(commandOnly: false, at: t0.addingTimeInterval(0.1)))
        XCTAssertFalse(hold.isHolding)
    }

    func testHoldBeginsOnceAfterThresholdAndEndsOnRelease() {
        var hold = CommandHold()
        _ = hold.modifiersChanged(commandOnly: true, at: t0)
        XCTAssertEqual(hold.tick(at: t0.addingTimeInterval(CommandHold.threshold)), .begin)
        XCTAssertNil(hold.tick(at: t0.addingTimeInterval(2)), "begin must fire only once")
        XCTAssertEqual(hold.modifiersChanged(commandOnly: false, at: t0.addingTimeInterval(3)), .end)
        XCTAssertFalse(hold.isHolding)
    }

    func testCommandShortcutCancelsBeforeThreshold() {
        var hold = CommandHold()
        _ = hold.modifiersChanged(commandOnly: true, at: t0)
        hold.otherKeyPressed()
        XCTAssertNil(hold.tick(at: t0.addingTimeInterval(1)), "⌘C must not start listening")
    }

    func testOtherKeyDuringHoldKeepsListening() {
        var hold = CommandHold()
        _ = hold.modifiersChanged(commandOnly: true, at: t0)
        _ = hold.tick(at: t0.addingTimeInterval(1))
        hold.otherKeyPressed()
        XCTAssertTrue(hold.isHolding, "a key pressed mid-speech must not stop recording")
    }

    func testAnotherModifierJoiningCancelsArming() {
        var hold = CommandHold()
        _ = hold.modifiersChanged(commandOnly: true, at: t0)
        XCTAssertNil(hold.modifiersChanged(commandOnly: false, at: t0.addingTimeInterval(0.1)))
        XCTAssertNil(hold.armedAt)
        XCTAssertNil(hold.tick(at: t0.addingTimeInterval(1)))
    }
}
