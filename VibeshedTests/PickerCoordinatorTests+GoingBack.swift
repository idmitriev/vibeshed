@testable import Vibeshed
import XCTest

/// Backspace on an empty field and the pill's ✕ go back a level like Escape; moving
/// through an action's parameters never adds levels to go back through.
extension PickerCoordinatorTests {
    private static let options = ["x", "y"].map { ParameterOption(id: $0, label: $0) }

    /// An action whose every parameter is a required choice between the options.
    private func pickAction(parameterIDs: [String]) -> MockAction {
        MockAction(
            id: ActionID(module: "mock", name: "pick"), title: "Pick", subtitle: "", iconName: nil,
            relevanceScore: 1, keywords: [],
            parameters: parameterIDs.map {
                ActionParameter(id: $0, label: $0, type: .selection(Self.options), isRequired: true)
            }
        )
    }

    func testGoingBackFromAPickedStepReturnsToTheSearch() async throws {
        let (coordinator, state) = try await makeCoordinator()
        coordinator.start()
        await coordinator.loadInitialActions().value
        let list = state.actions.map(\.id)

        state.enterParameterMode(action: pickAction(parameterIDs: ["one"]))

        XCTAssertNil(coordinator.goBack(), "the list beneath is put back, not reloaded")
        XCTAssertEqual(state.mode, .search)
        XCTAssertEqual(state.actions.map(\.id), list)
    }

    /// A keybinding's step has no list beneath it: going back leaves the action for a
    /// fresh search rather than doing nothing.
    func testGoingBackFromAKeybindingsStepOpensAFreshSearch() async throws {
        let (coordinator, state) = try await makeCoordinator()
        coordinator.start()
        state.enterParameterMode(action: pickAction(parameterIDs: ["one"]), asRoot: true)

        await coordinator.goBack()?.value

        XCTAssertEqual(state.mode, .search)
        XCTAssertFalse(state.canGoBack)
        XCTAssertNil(state.currentParameter)
        XCTAssertTrue(state.actions.contains { $0.id == ActionID(module: "mock", name: "calculator") })
    }

    /// Tab once stacked the next step over the current one, so Escape landed on the first
    /// parameter's mode while the second parameter's options were still up.
    func testReturnAndTabThroughParametersKeepOneLevelOverTheSearch() async throws {
        let (coordinator, state) = try await makeCoordinator()
        state.enterParameterMode(action: pickAction(parameterIDs: ["one", "two", "three"]))

        coordinator.handleReturn()
        XCTAssertEqual(state.currentParameter?.id, "two")
        coordinator.handleTab()
        XCTAssertEqual(state.currentParameter?.id, "three")

        XCTAssertTrue(state.popMode())
        XCTAssertEqual(state.mode, .search)
        XCTAssertFalse(state.canGoBack)
    }

    func testReturnAtAKeybindingsStepKeepsItTheRoot() async throws {
        let (coordinator, state) = try await makeCoordinator()
        state.enterParameterMode(action: pickAction(parameterIDs: ["one", "two"]), asRoot: true)

        coordinator.handleReturn()

        XCTAssertEqual(state.currentParameter?.id, "two")
        XCTAssertEqual(state.collectedValues, ["one": "x"])
        XCTAssertFalse(state.canGoBack, "Escape still closes the picker")
    }
}
