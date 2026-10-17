import AppKit
import Carbon.HIToolbox
@testable import Vibeshed
import XCTest

/// ⌘Escape closes the picker from any level, whatever lock state the keyboard is in.
@MainActor
final class FloatingPanelKeyTests: XCTestCase {
    private func escape(_ modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false,
            keyCode: UInt16(kVK_Escape)
        ))
    }

    /// Whether the key closes a panel (one per press: a hide in progress ignores another).
    private func closes(_ modifiers: NSEvent.ModifierFlags) throws -> Bool {
        let panel = FloatingPanel(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300))
        var hidden = false
        panel.onWillHide = { hidden = true }
        let handled = panel.performKeyEquivalent(with: try escape(modifiers))
        XCTAssertEqual(handled, hidden, "\(modifiers)")
        return hidden
    }

    func testCommandEscapeCloses() throws {
        XCTAssertTrue(try closes(.command))
    }

    /// Review of PR #79: with the Caps Lock light on, an exact match against
    /// `deviceIndependentFlagsMask` saw ⌘⇪Escape and did nothing.
    func testCommandEscapeClosesWithCapsLockOnOrAnExtendedKeyboard() throws {
        XCTAssertTrue(try closes([.command, .capsLock]))
        XCTAssertTrue(try closes([.command, .numericPad, .function]))
    }

    func testOtherEscapeChordsAreLeftAlone() throws {
        for modifiers: NSEvent.ModifierFlags in [[], [.command, .shift], [.command, .option], [.command, .control]] {
            XCTAssertFalse(try closes(modifiers), "\(modifiers)")
        }
    }
}
