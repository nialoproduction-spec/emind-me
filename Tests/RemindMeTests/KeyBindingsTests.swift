import AppKit
import Carbon.HIToolbox
import XCTest
@testable import RemindMe

/// Shortcuts default to Option, can be changed, and two actions can't share a key.
final class KeyBindingsTests: XCTestCase {
    func testDefaultsUseOption() {
        let bindings = KeyBindings()
        for action in KeyBindings.Action.allCases {
            XCTAssertEqual(bindings[action].flags, .option, "\(action)")
        }
        XCTAssertEqual(bindings.talk, .command, "double-press ⌘ to talk")
        XCTAssertEqual(bindings.talkMode, .doubleTap)
        XCTAssertEqual(bindings.done.display, "⌥D")
        XCTAssertEqual(bindings.undo.display, "⌥Z")
    }

    func testConflictFindsTheOtherAction() {
        let bindings = KeyBindings()
        XCTAssertEqual(bindings.conflict(for: bindings.done, except: .skip), .done)
        XCTAssertNil(bindings.conflict(for: bindings.done, except: .done))
    }

    func testOnlyUndoWorksAnytime() {
        XCTAssertFalse(KeyBindings.Action.undo.needsReminder)
        XCTAssertTrue(KeyBindings.Action.done.needsReminder)
    }

    func testOptionMapsToCarbonModifier() {
        XCTAssertEqual(KeyBinding.option("D", code: kVK_ANSI_D).carbonModifiers, UInt32(optionKey))
    }

    func testDisplayOrdersSymbols() {
        let binding = KeyBinding(keyCode: 40, modifiers: NSEvent.ModifierFlags([.command, .shift, .control]).rawValue, key: "K")
        XCTAssertEqual(binding.display, "⌃⇧⌘K")
    }

    func testSurvivesSavingAndLoading() throws {
        var bindings = KeyBindings()
        bindings.snooze = KeyBinding(keyCode: 1, modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue, key: "S")
        bindings.talk = .command
        let data = try JSONEncoder().encode(bindings)
        XCTAssertEqual(try JSONDecoder().decode(KeyBindings.self, from: data), bindings)
    }

    func testOldSavesSwitchToDoublePressCommandOnce() throws {
        let old = #"{"talk":"option"}"#.data(using: .utf8)!
        let loaded = try JSONDecoder().decode(KeyBindings.self, from: old)
        XCTAssertEqual(loaded.talk, .command)
        XCTAssertEqual(loaded.talkMode, .doubleTap)

        var mine = KeyBindings()
        mine.talk = .option
        mine.talkMode = .hold
        let back = try JSONDecoder().decode(KeyBindings.self, from: JSONEncoder().encode(mine))
        XCTAssertEqual(back.talk, .option, "a choice made after the switch is kept")
        XCTAssertEqual(back.talkMode, .hold)
    }

    func testDoubleTapStartsAndSingleTapsDont() {
        var taps = DoubleTap()
        let t = Date(timeIntervalSince1970: 100)
        XCTAssertNil(taps.modifiersChanged(talkOnly: true, anyModifier: true, at: t))
        XCTAssertEqual(taps.modifiersChanged(talkOnly: false, anyModifier: false, at: t.addingTimeInterval(0.1)), .tap)
        XCTAssertNil(taps.modifiersChanged(talkOnly: true, anyModifier: true, at: t.addingTimeInterval(0.25)))
        XCTAssertEqual(taps.modifiersChanged(talkOnly: false, anyModifier: false, at: t.addingTimeInterval(0.33)), .doubleTap)
    }

    func testSlowSecondTapIsJustATap() {
        var taps = DoubleTap()
        let t = Date(timeIntervalSince1970: 100)
        _ = taps.modifiersChanged(talkOnly: true, anyModifier: true, at: t)
        _ = taps.modifiersChanged(talkOnly: false, anyModifier: false, at: t.addingTimeInterval(0.1))
        _ = taps.modifiersChanged(talkOnly: true, anyModifier: true, at: t.addingTimeInterval(1.5))
        XCTAssertEqual(taps.modifiersChanged(talkOnly: false, anyModifier: false, at: t.addingTimeInterval(1.6)), .tap)
    }

    func testShortcutIsNotATap() {
        var taps = DoubleTap()
        let t = Date(timeIntervalSince1970: 100)
        _ = taps.modifiersChanged(talkOnly: true, anyModifier: true, at: t)
        taps.otherKeyPressed() // ⌘C
        XCTAssertNil(taps.modifiersChanged(talkOnly: false, anyModifier: false, at: t.addingTimeInterval(0.1)))
        // ⌘ then ⇧ joins: not a tap either.
        _ = taps.modifiersChanged(talkOnly: true, anyModifier: true, at: t.addingTimeInterval(1))
        XCTAssertNil(taps.modifiersChanged(talkOnly: false, anyModifier: true, at: t.addingTimeInterval(1.05)))
    }

    func testHeldKeyIsNotATap() {
        var taps = DoubleTap()
        let t = Date(timeIntervalSince1970: 100)
        _ = taps.modifiersChanged(talkOnly: true, anyModifier: true, at: t)
        XCTAssertNil(taps.modifiersChanged(talkOnly: false, anyModifier: false, at: t.addingTimeInterval(0.8)))
    }
}
