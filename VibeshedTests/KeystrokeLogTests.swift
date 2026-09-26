import Carbon.HIToolbox
import CoreGraphics
@testable import Vibeshed
import XCTest

final class KeystrokeLogTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    private func key(
        _ keyCode: Int,
        _ characters: String = "",
        modifiers: CGEventFlags = [],
        heldKey: KeystrokeEvent.HeldKey? = nil,
        outcome: KeystrokeEvent.Outcome = .passedThrough
    ) -> KeystrokeEvent {
        KeystrokeEvent(
            input: .key(keyCode: UInt16(keyCode), characters: characters),
            modifiers: modifiers,
            heldKey: heldKey,
            outcome: outcome
        )
    }

    // MARK: - Formatter

    func testComboLabelsUsePhysicalKeyInMenuOrder() {
        let chord = key(kVK_ANSI_C, "с", modifiers: [.maskCommand, .maskShift, .maskControl])
        XCTAssertEqual(KeystrokeFormatter.comboLabel(for: chord), "⌃⇧⌘C")
        XCTAssertEqual(KeystrokeFormatter.comboLabel(for: key(kVK_ANSI_Minus, "-", modifiers: .maskCommand)), "⌘-")
        XCTAssertEqual(KeystrokeFormatter.comboLabel(for: key(kVK_LeftArrow, modifiers: .maskAlternate)), "⌥←")
        XCTAssertEqual(KeystrokeFormatter.comboLabel(for: key(kVK_ANSI_H, "h", heldKey: .capsLock)), "⇪H")
        let mouse = KeystrokeEvent(input: .mouse(button: 3), modifiers: .maskShift, outcome: .passedThrough)
        XCTAssertEqual(KeystrokeFormatter.comboLabel(for: mouse), "⇧Mouse 4")
    }

    func testTypedTextKeepsLayoutCharactersAndRejectsChords() {
        XCTAssertEqual(KeystrokeFormatter.typedText(for: key(kVK_ANSI_Q, "й")), "й")
        XCTAssertEqual(KeystrokeFormatter.typedText(for: key(kVK_ANSI_A, "A", modifiers: .maskShift)), "A")
        XCTAssertEqual(KeystrokeFormatter.typedText(for: key(kVK_Space, " ")), "␣")
        XCTAssertEqual(KeystrokeFormatter.typedText(for: key(kVK_Delete, "\u{8}")), "⌫")
        XCTAssertNil(KeystrokeFormatter.typedText(for: key(kVK_ANSI_C, "c", modifiers: .maskCommand)))
        XCTAssertNil(KeystrokeFormatter.typedText(for: key(kVK_Return, "\r")))
        XCTAssertNil(KeystrokeFormatter.typedText(for: key(kVK_F13, "\u{F710}")))
        XCTAssertNil(KeystrokeFormatter.typedText(for: key(kVK_ANSI_H, "h", outcome: .binding(ActionID("a/b")))))
    }

    // MARK: - Log

    func testTypingRunsTogetherWithinMergeWindow() {
        var log = KeystrokeLog()
        log.record(key(kVK_ANSI_H, "h"), at: start)
        log.record(key(kVK_ANSI_I, "i"), at: start.addingTimeInterval(0.5))
        XCTAssertEqual(log.chips.map(\.text), ["hi"])

        log.record(key(kVK_ANSI_X, "x"), at: start.addingTimeInterval(0.5 + KeystrokeLog.mergeWindow))
        XCTAssertEqual(log.chips.map(\.text), ["hi", "x"])
    }

    func testLongTypingKeepsTheTail() {
        var log = KeystrokeLog()
        for _ in 0 ..< KeystrokeLog.maxTypingLength + 5 {
            log.record(key(kVK_ANSI_A, "a"), at: start)
        }
        log.record(key(kVK_ANSI_B, "b"), at: start)
        let text = log.chips.last?.text ?? ""
        XCTAssertEqual(text.count, KeystrokeLog.maxTypingLength)
        XCTAssertTrue(text.hasPrefix("…"))
        XCTAssertTrue(text.hasSuffix("ab"))
    }

    func testRepeatedChordBumpsCount() {
        var log = KeystrokeLog()
        let undo = key(kVK_ANSI_Z, "z", modifiers: .maskCommand)
        log.record(undo, at: start)
        log.record(undo, at: start.addingTimeInterval(0.2))
        log.record(undo, at: start.addingTimeInterval(0.4))
        XCTAssertEqual(log.chips.count, 1)
        XCTAssertEqual(log.chips.first?.text, "⌘Z")
        XCTAssertEqual(log.chips.first?.count, 3)
    }

    func testBindingsAndRemapsAreMarkedAsVibeshed() {
        var log = KeystrokeLog()
        let action = ActionID("window/tileLeft")
        let binding = log.record(key(kVK_ANSI_H, "h", heldKey: .capsLock, outcome: .binding(action)), at: start)
        XCTAssertEqual(binding.kind, .binding(action))
        XCTAssertTrue(binding.isVibeshed)

        let target = RemapTarget(keyCode: UInt16(kVK_LeftArrow), modifiers: .maskCommand)
        let remap = log.record(key(kVK_ANSI_H, "˙", modifiers: .maskAlternate, outcome: .remap(target)), at: start)
        XCTAssertEqual(remap.kind, .remap(target: "⌘←"))
        XCTAssertEqual(remap.text, "⌥H")
        XCTAssertTrue(remap.isVibeshed)

        let plain = log.record(key(kVK_ANSI_H, "h", modifiers: .maskCommand), at: start)
        XCTAssertFalse(plain.isVibeshed)
    }

    func testSameChordBoundVersusPassedThroughStaysSeparate() {
        var log = KeystrokeLog()
        log.record(key(kVK_ANSI_K, "k", modifiers: .maskCommand), at: start)
        log.record(key(kVK_ANSI_K, "k", modifiers: .maskCommand, outcome: .binding(ActionID("a/b"))), at: start)
        XCTAssertEqual(log.chips.count, 2)
    }

    func testCaptionAppliesToMatchingBindings() {
        var log = KeystrokeLog()
        let action = ActionID("window/tileLeft")
        log.record(key(kVK_ANSI_H, "h", heldKey: .capsLock, outcome: .binding(action)), at: start)
        log.record(key(kVK_ANSI_L, "l", heldKey: .capsLock, outcome: .binding(ActionID("a/b"))), at: start)
        log.setCaption("Tile Left", for: action)
        XCTAssertEqual(log.chips.map(\.caption), ["Tile Left", nil])
    }

    func testExpireSparesChipsUpdatedSince() {
        var log = KeystrokeLog()
        let chip = log.record(key(kVK_ANSI_A, "a"), at: start)
        log.record(key(kVK_ANSI_B, "b"), at: start.addingTimeInterval(1))
        log.expire(chip.id, ifUnchangedSince: start)
        XCTAssertEqual(log.chips.map(\.text), ["ab"])

        log.expire(chip.id, ifUnchangedSince: start.addingTimeInterval(1))
        XCTAssertTrue(log.chips.isEmpty)
    }

    func testOldestChipsDropPastLimit() {
        var log = KeystrokeLog()
        let keys = [kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E]
        for code in keys {
            log.record(key(code, modifiers: .maskCommand), at: start)
        }
        XCTAssertEqual(log.chips.map(\.text), ["⌘B", "⌘C", "⌘D", "⌘E"])
    }
}
