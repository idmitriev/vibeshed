@testable import Vibeshed
import XCTest

/// After a Shift run the picker takes keyboard focus back from an app the action
/// brought forward, but never from one the user switched to.
@MainActor
final class KeyFocusReclaimerTests: XCTestCase {
    func testReclaimsWhenTheLatestInputWasThePickers() {
        let reclaimer = KeyFocusReclaimer()
        reclaimer.recordLocalInput(at: 100) // ⇧Return in the picker
        // The HID system saw that same key press a hair earlier than the picker did.
        XCTAssertTrue(reclaimer.shouldReclaim(latestPhysicalInput: 99.98, now: 100.4))
    }

    func testLetsGoAfterInputElsewhere() {
        let reclaimer = KeyFocusReclaimer()
        reclaimer.recordLocalInput(at: 100)
        // A click on another window the picker never received.
        XCTAssertFalse(reclaimer.shouldReclaim(latestPhysicalInput: 101, now: 101.1))
    }

    func testTypingInThePickerKeepsLaterFocusLossesReclaimable() {
        let reclaimer = KeyFocusReclaimer()
        reclaimer.recordLocalInput(at: 100)
        reclaimer.recordLocalInput(at: 160) // still typing the next cask name
        // A long install launching its app a minute later.
        XCTAssertTrue(reclaimer.shouldReclaim(latestPhysicalInput: 160, now: 165))
    }

    func testGivesUpOnSomethingThatKeepsTakingFocus() {
        let reclaimer = KeyFocusReclaimer()
        reclaimer.recordLocalInput(at: 100)
        let attempts = [100.1, 100.3, 100.5, 100.7].map {
            reclaimer.shouldReclaim(latestPhysicalInput: 100, now: $0)
        }
        XCTAssertEqual(attempts, [true, true, true, false])
        // Once the burst is over, the next app coming forward is reclaimed again.
        XCTAssertTrue(reclaimer.shouldReclaim(latestPhysicalInput: 100, now: 103))
    }
}
