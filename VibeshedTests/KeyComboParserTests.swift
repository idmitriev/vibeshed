import CoreGraphics
@testable import Vibeshed
import XCTest

final class KeyComboParserTests: XCTestCase {
    func testStandardComboWithSingleModifier() throws {
        let space = try KeyComboParser.carbonKeyCode(for: "space")
        XCTAssertEqual(
            try KeyComboParser.parse("cmd+space"),
            .standard(carbonKeyCode: space, modifiers: [.maskCommand])
        )
    }

    func testStandardComboWithMultipleModifiers() throws {
        let pKey = try KeyComboParser.carbonKeyCode(for: "p")
        XCTAssertEqual(
            try KeyComboParser.parse("cmd+shift+p"),
            .standard(carbonKeyCode: pKey, modifiers: [.maskCommand, .maskShift])
        )
    }

    func testModifierAliases() throws {
        let aKey = try KeyComboParser.carbonKeyCode(for: "a")
        XCTAssertEqual(try KeyComboParser.parse("alt+a"), .standard(carbonKeyCode: aKey, modifiers: [.maskAlternate]))
        XCTAssertEqual(
            try KeyComboParser.parse("option+a"),
            .standard(carbonKeyCode: aKey, modifiers: [.maskAlternate])
        )
        XCTAssertEqual(try KeyComboParser.parse("ctrl+a"), .standard(carbonKeyCode: aKey, modifiers: [.maskControl]))
    }

    func testCaseInsensitive() throws {
        let space = try KeyComboParser.carbonKeyCode(for: "space")
        XCTAssertEqual(
            try KeyComboParser.parse("CMD+SPACE"),
            .standard(carbonKeyCode: space, modifiers: [.maskCommand])
        )
    }

    func testMouseButton() throws {
        // mouse4 → back button → zero-based CG button 3
        XCTAssertEqual(try KeyComboParser.parse("mouse4"), .mouseButton(button: 3, modifiers: []))
    }

    func testMouseButtonWithModifier() throws {
        XCTAssertEqual(
            try KeyComboParser.parse("cmd+mouse5"),
            .mouseButton(button: 4, modifiers: [.maskCommand])
        )
    }

    func testEmptyComboThrows() {
        XCTAssertThrowsError(try KeyComboParser.parse("")) { error in
            guard case let .invalidCombo(_, reason)? = error as? KeyComboError else {
                return XCTFail("expected invalidCombo, got \(error)")
            }
            XCTAssertTrue(reason.contains("empty"))
        }
    }

    func testUnknownKeyThrows() {
        XCTAssertThrowsError(try KeyComboParser.parse("cmd+foo")) { error in
            guard case let .unknownKey(key)? = error as? KeyComboError else {
                return XCTFail("expected unknownKey, got \(error)")
            }
            XCTAssertEqual(key, "foo")
        }
    }

    func testUnknownModifierThrows() {
        XCTAssertThrowsError(try KeyComboParser.parse("hyper+a")) { error in
            guard case let .unknownModifier(mod)? = error as? KeyComboError else {
                return XCTFail("expected unknownModifier, got \(error)")
            }
            XCTAssertEqual(mod, "hyper")
        }
    }
}
