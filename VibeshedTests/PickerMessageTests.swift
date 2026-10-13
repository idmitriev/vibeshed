@testable import Vibeshed
import XCTest

/// A result that couldn't be posted as a notification comes up as the picker's only row.
/// Dismissing it must leave the picker as it was: closed after a normal run, or back on
/// the session a Shift run left open, with that session's list rather than the message.
@MainActor
final class PickerMessageTests: XCTestCase {
    private let sessionActions = [
        MockAction(
            id: ActionID(module: "mock", name: "a"),
            title: "A",
            subtitle: "",
            iconName: nil,
            relevanceScore: 1,
            keywords: []
        ),
        MockAction(
            id: ActionID(module: "mock", name: "b"),
            title: "B",
            subtitle: "",
            iconName: nil,
            relevanceScore: 1,
            keywords: []
        ),
    ]

    private let message = PickerMessageAction(
        source: ActionID(module: "browser", name: "tab.x"),
        title: "Inbox",
        body: "Tab not found: Inbox",
        isFailure: true
    )

    /// A picker showing the session list, with B selected and "in" typed.
    private func makeSessionState() -> PickerState {
        let state = PickerState()
        state.updateActions(
            sessionActions.map(ActionItem.init(pushed:)),
            cache: Dictionary(uniqueKeysWithValues: sessionActions.map { ($0.id, $0 as any Action) })
        )
        state.selectedActionID = sessionActions[1].id
        state.query = "in"
        return state
    }

    private func showMessage(over state: PickerState) {
        state.pushMode(.pushedActions)
        state.updateActions([ActionItem(pushed: message)], cache: [message.id: message])
        state.query = "typed over the message"
    }

    func testPoppingMessageRestoresSessionList() {
        let state = makeSessionState()
        showMessage(over: state)
        XCTAssertEqual(state.actions.map(\.id), [message.id])

        XCTAssertTrue(state.popMode())

        XCTAssertEqual(state.mode, .search)
        XCTAssertEqual(state.actions.map(\.id), sessionActions.map(\.id))
        XCTAssertEqual(state.selectedActionID, sessionActions[1].id)
        XCTAssertEqual(state.query, "in")
        XCTAssertNotNil(state.actionCache[sessionActions[0].id])
        XCTAssertNil(state.actionCache[message.id])
    }

    /// A Shift run in a parameter step: the message covers that step, and the search
    /// list beneath it must survive for when the user backs out of the step.
    func testPoppingMessageOverParameterStepKeepsSearchList() {
        let state = makeSessionState()
        state.enterParameterMode(action: MockAction(
            id: ActionID(module: "mock", name: "pick"), title: "Pick", subtitle: "", iconName: nil,
            relevanceScore: 1, keywords: [],
            parameters: [ActionParameter(id: "item", label: "Item", type: .text(placeholder: nil), isRequired: true)]
        ))
        let parameterMode = state.mode
        showMessage(over: state)

        XCTAssertTrue(state.popMode())
        XCTAssertEqual(state.mode, parameterMode)
        XCTAssertTrue(state.popMode())
        XCTAssertEqual(state.mode, .search)
        XCTAssertEqual(state.actions.map(\.id), sessionActions.map(\.id))
    }

    func testRootMessageHasNothingToGoBackTo() {
        let state = PickerState()
        state.showAsRoot(.pushedActions)
        state.updateActions([ActionItem(pushed: message)], cache: [message.id: message])

        XCTAssertEqual(state.mode, .pushedActions)
        XCTAssertFalse(state.popMode(), "Escape closes the picker instead of going back")
    }

    func testActivatingMessageReturnsToSessionWithoutRunningIt() {
        let eventBus = EventBus()
        let configManager = ConfigManager(eventBus: eventBus)
        let registry = ModuleRegistry(
            eventBus: eventBus,
            configManager: configManager,
            permissionsManager: PermissionsManager(eventBus: eventBus)
        )
        let state = makeSessionState()
        let coordinator = PickerCoordinator(
            pickerState: state,
            moduleRegistry: registry,
            panelController: PanelController(pickerState: state, configManager: configManager),
            eventBus: eventBus
        )
        showMessage(over: state)

        coordinator.activateAction(id: message.id)

        XCTAssertEqual(state.mode, .search)
        XCTAssertEqual(state.actions.map(\.id), sessionActions.map(\.id))
    }
}
