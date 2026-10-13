@testable import Vibeshed
import XCTest

/// Where the highlight goes when the list is replaced: a refresh (the same text ranked
/// again) keeps the highlighted row, matched by ID; new text starts on the first row.
@MainActor
final class PickerSelectionTests: XCTestCase {
    private func rows(_ names: String...) -> [ActionItem] {
        names.map { ActionItem(id: id($0), title: $0, subtitle: "") }
    }

    private func id(_ name: String) -> ActionID {
        ActionID(module: "mock", name: name)
    }

    func testRefreshKeepsTheHighlightedRowWhereverItMoves() {
        let state = PickerState()
        state.updateActions(rows("event", "search", "reviews"), rankedFor: "pr")
        state.selectNext()
        let resets = state.listResetToken
        let reveals = state.selectionRevealToken

        state.updateActions(rows("event", "reviews", "search"), rankedFor: "pr")

        XCTAssertEqual(state.selectedActionID, id("search"))
        XCTAssertEqual(state.listResetToken, resets, "the list stays where it is")
        XCTAssertEqual(state.selectionRevealToken, reveals + 1, "the moved row is scrolled into view")
    }

    func testRefreshThatDropsTheHighlightedRowSelectsTheRowInItsPlace() {
        let state = PickerState()
        state.updateActions(rows("a", "b", "c"), rankedFor: "x")
        state.selectNext()

        state.updateActions(rows("a", "c"), rankedFor: "x")
        XCTAssertEqual(state.selectedActionID, id("c"))

        state.updateActions(rows("a"), rankedFor: "x")
        XCTAssertEqual(state.selectedActionID, id("a"), "the last row goes to the new last row")
    }

    func testNewTextStartsOnTheFirstRow() {
        let state = PickerState()
        state.updateActions(rows("a", "b"), rankedFor: "p")
        state.selectNext()
        let resets = state.listResetToken

        state.updateActions(rows("a", "b"), rankedFor: "pr")

        XCTAssertEqual(state.selectedActionID, id("a"))
        XCTAssertEqual(state.listResetToken, resets + 1)
    }

    /// The cached list shown at open is the last session's; this session's first ranking
    /// may put something else first (a meeting about to start).
    func testFirstRankingAfterTheCachedListStartsOnTheFirstRow() {
        let state = PickerState()
        state.updateActions(rows("a", "b", "c"))
        state.selectNext()

        state.updateActions(rows("c", "a", "b"), rankedFor: "")

        XCTAssertEqual(state.selectedActionID, id("c"))
    }

    func testListRestoredFromUnderAMessageStillRefreshes() {
        let state = PickerState()
        state.updateActions(rows("a", "b"), rankedFor: "pr")
        state.selectNext()
        state.pushMode(.pushedActions)
        state.updateActions(rows("message"))
        XCTAssertTrue(state.popMode())

        state.updateActions(rows("b", "a"), rankedFor: "pr")

        XCTAssertEqual(state.selectedActionID, id("b"))
    }
}
