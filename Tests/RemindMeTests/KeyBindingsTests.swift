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
        XCTAssertEqual(bindings.talk, .option)
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
}
