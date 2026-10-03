@testable import Vibeshed
import XCTest

@MainActor
final class SelectionScrollTrackerTests: XCTestCase {
    // Rows 52pt tall, 2pt apart; viewport shows y 70...400.
    private let pitch: CGFloat = 54
    private let visible: ClosedRange<CGFloat> = 70 ... 400

    private func row(minY: CGFloat) -> CGRect {
        CGRect(x: 0, y: minY, width: 600, height: 52)
    }

    private func corrected(index: Int, minY: CGFloat, count: Int = 50) -> Int? {
        SelectionScrollTracker<Int>.correctedIndex(
            selectedIndex: index,
            selectedFrame: row(minY: minY),
            rowPitch: pitch,
            visible: visible,
            count: count
        )
    }

    func testFullyVisibleRowKeepsSelection() {
        XCTAssertNil(corrected(index: 5, minY: 200))
    }

    func testRowFlushAgainstEdgesKeepsSelection() {
        XCTAssertNil(corrected(index: 5, minY: 70))
        XCTAssertNil(corrected(index: 5, minY: 348))
        XCTAssertNil(corrected(index: 5, minY: 69)) // within slack
    }

    func testScrolledAboveTopSelectsFirstFullyVisibleRow() {
        // Row 5 partly hidden under the top edge → row 6 starts at 104.
        XCTAssertEqual(corrected(index: 5, minY: 50), 6)
        // Scrolled three rows past → row 8 starts at 70 + 3.
        XCTAssertEqual(corrected(index: 5, minY: -89), 8)
    }

    func testScrolledBelowBottomSelectsLastFullyVisibleRow() {
        // Row 5 ends at 432 → row 4 ends at 378.
        XCTAssertEqual(corrected(index: 5, minY: 380), 4)
    }

    func testCorrectionClampsToListBounds() {
        XCTAssertEqual(corrected(index: 48, minY: -500, count: 50), 49)
        XCTAssertEqual(corrected(index: 1, minY: 900), 0)
    }

    private func makeTracker() -> SelectionScrollTracker<Int> {
        let tracker = SelectionScrollTracker<Int>()
        tracker.visibleTop = 70
        tracker.viewportHeight = 400
        tracker.scrollToApplied()
        return tracker
    }

    /// Content top such that row `index` starts at `rowMinY`.
    private func move(_ tracker: SelectionScrollTracker<Int>, selected: Int, rowMinY: CGFloat) -> Int? {
        tracker.contentMoved(
            contentMinY: rowMinY - CGFloat(selected) * pitch,
            selectedID: selected,
            ids: Array(0 ..< 50),
            rowHeight: 52,
            rowSpacing: 2
        )
    }

    func testFlickFarPastSelectionStillCorrects() {
        let tracker = makeTracker()
        // One frame carries row 5 a whole screen above the viewport.
        XCTAssertEqual(move(tracker, selected: 5, rowMinY: -900), 23)
        // The tracker's own pick must not trigger `scrollTo`.
        XCTAssertFalse(tracker.selectionChanged(to: 23))
    }

    func testConsecutiveCorrectionsAllSkipScrollTo() {
        let tracker = makeTracker()
        XCTAssertEqual(move(tracker, selected: 5, rowMinY: 20), 6)
        XCTAssertEqual(move(tracker, selected: 6, rowMinY: 50), 7)
        // SwiftUI may deliver either or both `onChange`s afterwards.
        XCTAssertFalse(tracker.selectionChanged(to: 6))
        XCTAssertFalse(tracker.selectionChanged(to: 7))
    }

    func testKeyboardSelectionIsNotCorrectedUntilScrollToLands() {
        let tracker = makeTracker()
        XCTAssertTrue(tracker.selectionChanged(to: 20))
        // Before `scrollTo` lands the row is still offscreen — leave it alone.
        XCTAssertNil(move(tracker, selected: 20, rowMinY: 900))
        tracker.scrollToApplied()
        // Later wheel scrolling is followed again.
        XCTAssertNil(move(tracker, selected: 20, rowMinY: 348))
        XCTAssertEqual(move(tracker, selected: 20, rowMinY: 380), 19)
    }

    func testClickSelectionFollowsScrollOnceScrollToApplied() {
        let tracker = makeTracker()
        XCTAssertTrue(tracker.selectionChanged(to: 5))
        tracker.scrollToApplied()
        XCTAssertEqual(move(tracker, selected: 5, rowMinY: -900), 23)
    }

    func testFreshListWaitsForInitialScrollToBeforeCorrecting() {
        let tracker = SelectionScrollTracker<Int>()
        tracker.visibleTop = 70
        // First report can arrive before the viewport is measured.
        XCTAssertNil(move(tracker, selected: 30, rowMinY: 70 + 30 * pitch))
        tracker.viewportHeight = 400
        // First layout jumps: target, back to the top, target again — all before
        // `scrollTo` is applied, none of them a user scroll.
        XCTAssertNil(move(tracker, selected: 30, rowMinY: 200))
        XCTAssertNil(move(tracker, selected: 30, rowMinY: 70 + 30 * pitch))
        tracker.scrollToApplied()
        XCTAssertNil(move(tracker, selected: 30, rowMinY: 200))
        XCTAssertEqual(move(tracker, selected: 30, rowMinY: 20), 31)
    }

    func testUnmeasuredViewportNeverCorrects() {
        let tracker = SelectionScrollTracker<Int>()
        tracker.visibleTop = 70
        tracker.scrollToApplied()
        XCTAssertNil(move(tracker, selected: 30, rowMinY: 2000))
    }

    func testCoalescedCorrectionDoesNotLeaveStaleIDs() {
        let tracker = makeTracker()
        XCTAssertEqual(move(tracker, selected: 5, rowMinY: 20), 6)
        XCTAssertEqual(move(tracker, selected: 6, rowMinY: 50), 7)
        // SwiftUI delivers a single `onChange` for the final value only.
        XCTAssertFalse(tracker.selectionChanged(to: 7))
        // A later keyboard move to 6 is a real selection and must scroll.
        XCTAssertTrue(tracker.selectionChanged(to: 6))
    }

    func testReusedTrackerWaitsAgainWhenListReappears() {
        let tracker = makeTracker()
        // The list is re-inserted (options reloaded) with a preset selection off screen.
        tracker.scrollToStarting()
        XCTAssertNil(move(tracker, selected: 30, rowMinY: 70 + 30 * pitch))
        tracker.scrollToApplied()
        XCTAssertNil(move(tracker, selected: 30, rowMinY: 200))
    }
}
