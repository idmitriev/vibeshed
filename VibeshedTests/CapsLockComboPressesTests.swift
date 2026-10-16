import Carbon.HIToolbox
@testable import Vibeshed
import XCTest

final class CapsLockComboPressesTests: XCTestCase {
    private let space = UInt16(kVK_Space)
    private let minus = UInt16(kVK_ANSI_Minus)

    func testComboOwnsItsRepeatsAndKeyUp() {
        var presses = CapsLockComboPresses()
        XCTAssertEqual(presses.keyDown(space, isRepeat: false, comboIsHeld: true), .fire)
        XCTAssertEqual(presses.keyDown(space, isRepeat: true, comboIsHeld: true), .fire)
        XCTAssertTrue(presses.keyUp(space))
        XCTAssertFalse(presses.keyUp(space), "a second keyUp isn't part of the press")
    }

    func testReleasingCapsLockFirstKeepsTheComboKeyFromTheApp() {
        var presses = CapsLockComboPresses()
        XCTAssertEqual(presses.keyDown(minus, isRepeat: false, comboIsHeld: true), .fire)
        XCTAssertEqual(presses.keyDown(minus, isRepeat: true, comboIsHeld: false), .swallow)
        XCTAssertEqual(presses.keyDown(minus, isRepeat: true, comboIsHeld: false), .swallow)
        XCTAssertTrue(presses.keyUp(minus))
    }

    func testCapsLockDownMidPressDoesNotTakeOverTheAppsKey() {
        // Space reached YouTube first (pressed before capslock, or capslock
        // registered late); its repeats must not toggle the picker.
        var presses = CapsLockComboPresses()
        XCTAssertEqual(presses.keyDown(space, isRepeat: false, comboIsHeld: false), .pass)
        XCTAssertEqual(presses.keyDown(space, isRepeat: true, comboIsHeld: true), .pass)
        XCTAssertEqual(presses.keyDown(space, isRepeat: true, comboIsHeld: true), .pass)
        XCTAssertFalse(presses.keyUp(space))
    }

    func testNewPressClearsAComboWhoseKeyUpWasMissed() {
        var presses = CapsLockComboPresses()
        XCTAssertEqual(presses.keyDown(space, isRepeat: false, comboIsHeld: true), .fire)
        // keyUp never reached the tap; the next plain press must reach the app whole.
        XCTAssertEqual(presses.keyDown(space, isRepeat: false, comboIsHeld: false), .pass)
        XCTAssertEqual(presses.keyDown(space, isRepeat: true, comboIsHeld: false), .pass)
        XCTAssertFalse(presses.keyUp(space))
    }

    func testKeysAreTrackedSeparately() {
        var presses = CapsLockComboPresses()
        XCTAssertEqual(presses.keyDown(space, isRepeat: false, comboIsHeld: true), .fire)
        XCTAssertEqual(presses.keyDown(minus, isRepeat: false, comboIsHeld: false), .pass)
        XCTAssertFalse(presses.keyUp(minus))
        XCTAssertTrue(presses.keyUp(space))
    }
}
