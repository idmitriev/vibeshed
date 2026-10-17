@testable import Vibeshed
import XCTest

/// Escape goes back one level, to where the user came from in this picker session, and
/// closes the picker at the root. A list or step that came up on its own — a closing
/// run's results, the browser chooser, a keybinding's parameter step — is the root, so
/// Escape closes it instead of flashing a list the user never saw.
@MainActor
final class PickerModeStackTests: XCTestCase {
    private let rows = ["a", "b", "c"].map {
        MockAction(
            id: ActionID(module: "mock", name: $0), title: $0.uppercased(), subtitle: "", iconName: nil,
            relevanceScore: 1, keywords: []
        )
    }

    private let pushedRows = ["pr1", "pr2"].map {
        MockAction(
            id: ActionID(module: "github", name: $0), title: $0, subtitle: "", iconName: nil,
            relevanceScore: 1, keywords: []
        )
    }

    private let options = ["x", "y"].map { ParameterOption(id: $0, label: $0) }

    /// A picker on the search list, with B selected and "b" typed.
    private func makeSearchState() -> PickerState {
        let state = PickerState()
        show(rows, in: state)
        state.selectedActionID = rows[1].id
        state.query = "b"
        return state
    }

    private func show(_ actions: [MockAction], in state: PickerState) {
        state.updateActions(
            actions.map(ActionItem.init(pushed:)),
            cache: Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0 as any Action) })
        )
    }

    /// An action whose every parameter is a required choice between the options.
    private func action(parameterIDs: [String]) -> MockAction {
        MockAction(
            id: ActionID(module: "mock", name: "pick"), title: "Pick", subtitle: "", iconName: nil,
            relevanceScore: 1, keywords: [],
            parameters: parameterIDs.map {
                ActionParameter(id: $0, label: $0, type: .selection(options), isRequired: true)
            }
        )
    }

    private func assertOnSearchList(_ state: PickerState, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(state.mode, .search, file: file, line: line)
        XCTAssertEqual(state.actions.map(\.id), rows.map(\.id), file: file, line: line)
        XCTAssertEqual(state.selectedActionID, rows[1].id, file: file, line: line)
        XCTAssertEqual(state.query, "b", file: file, line: line)
        XCTAssertFalse(state.canGoBack, file: file, line: line)
    }

    // MARK: - Pushed lists

    func testEscapeFromAPushedListPutsBackTheListItCovered() {
        let state = makeSearchState()
        state.pushMode(.pushedActions)
        show(pushedRows, in: state)
        state.query = "typed over the pushed list"
        XCTAssertTrue(state.canGoBack)

        XCTAssertTrue(state.popMode())

        assertOnSearchList(state)
        XCTAssertNotNil(state.actionCache[rows[0].id])
        XCTAssertNil(state.actionCache[pushedRows[0].id])
    }

    /// The 0.10.0 report: GitHub's PR results, pushed after the run had closed and reset
    /// the picker, went "back" to that reset search on Escape — still listing the PRs —
    /// and only a second Escape closed it.
    func testAListShownAsRootHasNothingToGoBackTo() {
        let state = makeSearchState()
        state.enterParameterMode(action: action(parameterIDs: ["one"]))
        XCTAssertTrue(state.canGoBack)

        state.showAsRoot(.pushedActions)
        show(pushedRows, in: state)

        XCTAssertFalse(state.canGoBack)
        XCTAssertFalse(state.popMode(), "Escape closes the picker")
        XCTAssertEqual(state.mode, .pushedActions)
        XCTAssertEqual(state.actions.map(\.id), pushedRows.map(\.id))
        XCTAssertNil(state.currentParameter, "the covered step is gone with the stack")
    }

    // MARK: - Parameter steps

    func testEscapeFromAStepReturnsToTheSearchItWasPickedFrom() {
        let state = makeSearchState()
        let pick = action(parameterIDs: ["one"])
        state.enterParameterMode(action: pick)
        state.parameterQuery = "x"
        XCTAssertEqual(state.mode, .parameterInput(actionID: pick.id, parameterIndex: 0))

        XCTAssertTrue(state.popMode())

        assertOnSearchList(state)
        XCTAssertEqual(state.parameterQuery, "")
        XCTAssertNil(state.currentParameter)
        XCTAssertEqual(state.parameterOptions, [])
    }

    func testTheNextParameterTakesThePlaceOfTheStep() {
        let state = makeSearchState()
        let pick = action(parameterIDs: ["one", "two"])
        state.enterParameterMode(action: pick)
        state.confirmParameterValue("x", forParameterID: "one")

        state.advanceToNextParameter(startingFrom: 1)

        XCTAssertEqual(state.mode, .parameterInput(actionID: pick.id, parameterIndex: 1))
        XCTAssertEqual(state.currentParameter?.id, "two")
        XCTAssertTrue(state.popMode())
        assertOnSearchList(state)
    }

    func testAStepOverAPushedListGoesBackToThatList() {
        let state = PickerState()
        state.showAsRoot(.pushedActions)
        show(pushedRows, in: state)
        state.selectedActionID = pushedRows[1].id

        state.enterParameterMode(action: action(parameterIDs: ["one"]))
        XCTAssertTrue(state.popMode())

        XCTAssertEqual(state.mode, .pushedActions)
        XCTAssertEqual(state.actions.map(\.id), pushedRows.map(\.id))
        XCTAssertEqual(state.selectedActionID, pushedRows[1].id)
        XCTAssertNil(state.currentParameter)
        XCTAssertFalse(state.canGoBack)
    }

    // MARK: - A keybinding's parameter step

    func testAKeybindingsStepIsTheRoot() {
        let state = makeSearchState()
        state.pushMode(.pushedActions)
        let pick = action(parameterIDs: ["one"])

        state.enterParameterMode(action: pick, asRoot: true)

        XCTAssertEqual(state.mode, .parameterInput(actionID: pick.id, parameterIndex: 0))
        XCTAssertFalse(state.canGoBack)
        XCTAssertFalse(state.popMode(), "Escape closes the picker")
        XCTAssertEqual(state.currentParameter?.id, "one")
    }

    func testAKeybindingsStepStaysTheRootThroughLaterParameters() {
        let state = PickerState()
        let pick = action(parameterIDs: ["one", "two"])
        state.enterParameterMode(action: pick, asRoot: true)
        state.confirmParameterValue("x", forParameterID: "one")

        state.advanceToNextParameter(startingFrom: 1)

        XCTAssertEqual(state.mode, .parameterInput(actionID: pick.id, parameterIndex: 1))
        XCTAssertFalse(state.canGoBack)
    }

    // MARK: - Hiding with the toggle hotkey

    func testAHiddenPickerKeepsItsPlaceOnlyUntilResetAfter() {
        let picker = AppConfig.PickerConfig()
        XCTAssertTrue(picker.keepsState(hiddenFor: 0))
        XCTAssertTrue(picker.keepsState(hiddenFor: picker.resetAfter - 0.1))
        XCTAssertFalse(picker.keepsState(hiddenFor: picker.resetAfter))
        XCTAssertFalse(picker.keepsState(hiddenFor: 300))

        XCTAssertFalse(AppConfig.PickerConfig(resetAfter: 0).keepsState(hiddenFor: 0), "0 always opens fresh")
    }
}
