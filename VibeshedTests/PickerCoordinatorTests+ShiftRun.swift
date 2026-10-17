@testable import Vibeshed
import XCTest

/// Shift runs (⇧Return, ⇧double-click, ⌘⇧1–9) run the action but leave the picker as it
/// was, minus what was typed, so the next similar run is a query and a Return away.
extension PickerCoordinatorTests {
    private static let options: [ParameterOption] = ["firefox", "slack", "zed"].map {
        ParameterOption(id: $0, label: $0)
    }

    private func waitForRuns(_ log: RunLog, count: Int) async throws -> [ParameterValues] {
        for _ in 0 ..< 100 where await log.values.count < count {
            try await Task.sleep(for: .milliseconds(10))
        }
        return await log.values
    }

    func testShiftRunStaysOnTheParameterStep() async throws {
        let (coordinator, state) = try await makeCoordinator()
        coordinator.start()
        let log = RunLog()
        let install = RecordingAction(
            id: ActionID(module: "mock", name: "install"),
            parameters: [
                ActionParameter(id: "name", label: "Name", type: .selection(Self.options), isRequired: true),
            ],
            log: log
        )
        state.enterParameterMode(action: install)
        state.parameterQuery = "sl"
        state.selectedParameterOptionID = "slack"

        coordinator.handleReturn(keepOpen: true)

        XCTAssertEqual(state.mode, .parameterInput(actionID: install.id, parameterIndex: 0))
        XCTAssertEqual(state.parameterQuery, "")
        XCTAssertEqual(state.collectedValues, [:], "the step is open for another value")
        XCTAssertEqual(state.optionActivationCounters["slack"], 1)

        state.selectedParameterOptionID = "zed"
        coordinator.handleReturn(keepOpen: true)

        let runs = try await waitForRuns(log, count: 2)
        XCTAssertEqual(runs, [["name": "slack"], ["name": "zed"]])
        XCTAssertEqual(state.activeAction?.id, install.id)
    }

    func testCmdShiftNumberPicksTheOptionAndStaysOnTheStep() async throws {
        let (coordinator, state) = try await makeCoordinator()
        coordinator.start()
        let log = RunLog()
        let install = RecordingAction(
            id: ActionID(module: "mock", name: "install"),
            parameters: [
                ActionParameter(id: "name", label: "Name", type: .selection(Self.options), isRequired: true),
            ],
            log: log
        )
        state.enterParameterMode(action: install)

        coordinator.handleCmdNumber(2, keepOpen: true)
        coordinator.handleCmdNumber(3, keepOpen: true)

        XCTAssertEqual(state.mode, .parameterInput(actionID: install.id, parameterIndex: 0))
        XCTAssertEqual(state.collectedValues, [:])
        let runs = try await waitForRuns(log, count: 2)
        XCTAssertEqual(runs, [["name": "slack"], ["name": "zed"]])
    }

    func testShiftRunKeepsEarlierStepsValues() async throws {
        let (coordinator, state) = try await makeCoordinator()
        coordinator.start()
        let log = RunLog()
        let action = RecordingAction(
            id: ActionID(module: "mock", name: "install"),
            parameters: [
                ActionParameter(
                    id: "kind", label: "Kind",
                    type: .selection([ParameterOption(id: "cask", label: "Cask")]),
                    isRequired: true
                ),
                ActionParameter(id: "name", label: "Name", type: .selection(Self.options), isRequired: true),
            ],
            log: log
        )
        state.enterParameterMode(action: action)
        coordinator.handleReturn() // Kind: Cask
        XCTAssertEqual(state.currentParameter?.id, "name")

        state.selectedParameterOptionID = "firefox"
        coordinator.handleReturn(keepOpen: true)

        XCTAssertEqual(state.mode, .parameterInput(actionID: action.id, parameterIndex: 1))
        XCTAssertEqual(state.collectedValues, ["kind": "cask"])
        let runs = try await waitForRuns(log, count: 1)
        XCTAssertEqual(runs, [["kind": "cask", "name": "firefox"]])
    }

    func testShiftRunFromTheListClearsOnlyTheQuery() async throws {
        let log = RunLog()
        let (coordinator, state) = try await makeCoordinator(module: RecordingModule(log: log))
        state.query = "ping"
        await coordinator.loadInitialActions().value
        let ping = ActionID(module: "recording", name: "ping")
        XCTAssertEqual(state.selectedActionID, ping)

        coordinator.handleReturn(keepOpen: true)

        XCTAssertEqual(state.query, "")
        XCTAssertEqual(state.mode, .search)
        XCTAssertEqual(state.activationCounters[ping], 1)
        let runs = try await waitForRuns(log, count: 1)
        XCTAssertEqual(runs, [[:]])
    }
}

/// Every run's values, in order.
actor RunLog {
    private(set) var values: [ParameterValues] = []

    func append(_ runValues: ParameterValues) {
        values.append(runValues)
    }
}

struct RecordingAction: Action {
    let id: ActionID
    var title: String {
        id.actionName
    }

    let subtitle = ""
    let iconName: String? = nil
    let relevanceScore = 1.0
    let keywords: [String] = []
    var parameters: [ActionParameter] = []
    let log: RunLog

    func run(with values: ParameterValues) async throws -> ActionResult {
        await log.append(values)
        return .dismiss
    }
}

/// A catalog of one parameterless action that records its runs.
private actor RecordingModule: Module {
    let id = "recording"
    let displayName = "Recording"
    let iconName = "sparkle"
    var isEnabled = true
    let log: RunLog

    init(log: RunLog) {
        self.log = log
    }

    func initialize(context _: ModuleContext) async throws {}

    func provideActions(query _: String, scoring _: ScoringContext) async -> [any Action] {
        [RecordingAction(id: ActionID(module: id, name: "ping"), log: log)]
    }
}
