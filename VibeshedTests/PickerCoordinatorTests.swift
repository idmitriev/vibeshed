@testable import Vibeshed
import XCTest

/// The initial load after the show animation must rank the text already in the
/// search field — a `vibeshed://picker?q=` query, or keys typed during the
/// animation — rather than "". It supersedes their debounced query, so loading ""
/// left the field and the list out of sync.
@MainActor
final class PickerCoordinatorTests: XCTestCase {
    private let calculator = ActionID(module: "mock", name: "calculator")

    /// A coordinator whose whole catalog is `MockModule`'s fixture actions, of
    /// which only Calculator matches "calc".
    private func makeCoordinator(module: any Module = MockModule()) async throws -> (PickerCoordinator, PickerState) {
        let eventBus = EventBus()
        let configManager = ConfigManager(eventBus: eventBus)
        let registry = ModuleRegistry(
            eventBus: eventBus,
            configManager: configManager,
            permissionsManager: PermissionsManager(eventBus: eventBus)
        )
        try await registry.register(module)
        let state = PickerState()
        let coordinator = PickerCoordinator(
            pickerState: state,
            moduleRegistry: registry,
            panelController: PanelController(pickerState: state, configManager: configManager),
            eventBus: eventBus
        )
        return (coordinator, state)
    }

    func testInitialLoadRanksQueryAlreadyInField() async throws {
        let (coordinator, state) = try await makeCoordinator()
        state.query = "calc"

        await coordinator.loadInitialActions().value

        XCTAssertEqual(state.actions.map(\.id), [calculator])
        XCTAssertEqual(state.selectedActionID, calculator)
    }

    func testInitialLoadWithQueryKeepsEmptyQueryCache() async throws {
        let (coordinator, state) = try await makeCoordinator()
        await coordinator.loadInitialActions().value
        let unfiltered = state.actions.map(\.id)
        XCTAssertGreaterThan(unfiltered.count, 1, "an empty query lists the whole catalog")

        state.reset()
        state.query = "calc"
        await coordinator.loadInitialActions().value
        XCTAssertEqual(state.actions.map(\.id), [calculator])

        // The next plain open shows the cache before its own load runs — it must
        // still hold the empty-query list, not the "calc" results.
        state.reset()
        coordinator.showCachedActionsIfAvailable()
        XCTAssertEqual(state.actions.map(\.id), unfiltered)
    }

    func testSlowParameterOptionsDontOverwriteNewerOnes() async throws {
        let (coordinator, state) = try await makeCoordinator(module: OutOfOrderOptionsModule())
        coordinator.start()
        state.enterParameterMode(action: MockAction(
            id: ActionID(module: "outOfOrder", name: "pick"),
            title: "Pick",
            subtitle: "",
            iconName: nil,
            relevanceScore: 1,
            keywords: [],
            parameters: [
                ActionParameter(id: "item", label: "Item", type: .dynamicSelection(hint: ""), isRequired: true),
            ]
        ))

        state.parameterQuery = "a"
        try await Task.sleep(for: .milliseconds(250)) // past the debounce: the slow fetch is running
        state.parameterQuery = "ab"
        try await Task.sleep(for: .milliseconds(800)) // the "ab" options land, then the late "a" ones

        XCTAssertEqual(state.parameterOptions.map(\.id), ["ab"])
    }

    /// Search results whose titles don't contain the query (a painting found by its
    /// description) stay listed, in the module's order.
    func testRankedByModuleOptionsSkipFuzzyFiltering() async throws {
        for rankedByModule in [false, true] {
            let (coordinator, state) = try await makeCoordinator(module: SearchResultsModule())
            coordinator.start()
            state.enterParameterMode(action: MockAction(
                id: ActionID(module: "searchResults", name: "pick"),
                title: "Pick",
                subtitle: "",
                iconName: nil,
                relevanceScore: 1,
                keywords: [],
                parameters: [
                    ActionParameter(
                        id: "item", label: "Item", type: .dynamicSelection(hint: ""), isRequired: true,
                        rankedByModule: rankedByModule
                    ),
                ]
            ))
            state.parameterQuery = "storm"
            try await Task.sleep(for: .milliseconds(300))

            XCTAssertEqual(
                state.parameterOptions.map(\.id),
                rankedByModule ? ["gust", "storm", "tivoli"] : ["storm"]
            )
        }
    }
}

extension PickerCoordinatorTests {
    /// A dynamic selection's options can depend on what an earlier parameter was set to
    /// (a search scoped by the source picked first).
    func testLaterOptionsSeeEarlierValues() async throws {
        let (coordinator, state) = try await makeCoordinator(module: ScopedOptionsModule())
        coordinator.start()
        state.enterParameterMode(action: MockAction(
            id: ActionID(module: "scoped", name: "search"),
            title: "Search",
            subtitle: "",
            iconName: nil,
            relevanceScore: 1,
            keywords: [],
            parameters: [
                ActionParameter(
                    id: "source", label: "Source",
                    type: .selection([
                        ParameterOption(id: "all", label: "All"), ParameterOption(id: "met", label: "Met"),
                    ]),
                    isRequired: true
                ),
                ActionParameter(id: "item", label: "Item", type: .dynamicSelection(hint: ""), isRequired: true),
            ]
        ))
        state.selectedParameterOptionID = "met"
        coordinator.handleReturn()
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(state.currentParameter?.id, "item")
        XCTAssertEqual(state.parameterOptions.map(\.id), ["met"])
    }
}

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
private actor RunLog {
    private(set) var values: [ParameterValues] = []

    func append(_ runValues: ParameterValues) {
        values.append(runValues)
    }
}

private struct RecordingAction: Action {
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

/// Lists the source picked in the action's first parameter.
private actor ScopedOptionsModule: Module {
    let id = "scoped"
    let displayName = "Scoped"
    let iconName = "sparkle"
    var isEnabled = true

    func initialize(context _: ModuleContext) async throws {}

    func provideActions(query _: String, scoring _: ScoringContext) async -> [any Action] {
        []
    }

    func provideParameterOptions(
        for _: String, in _: ActionID, query _: String, collected: ParameterValues
    ) async -> [ParameterOption] {
        [ParameterOption(id: collected["source"] ?? "none", label: collected["source"] ?? "none")]
    }
}

/// Answers any query with the same three paintings, as a remote search would.
private actor SearchResultsModule: Module {
    let id = "searchResults"
    let displayName = "Search Results"
    let iconName = "sparkle"
    var isEnabled = true

    func initialize(context _: ModuleContext) async throws {}

    func provideActions(query _: String, scoring _: ScoringContext) async -> [any Action] {
        []
    }

    func provideParameterOptions(for _: String, in _: ActionID, query _: String) async -> [ParameterOption] {
        [
            ParameterOption(id: "gust", label: "A Ship on the High Seas Caught by a Squall"),
            ParameterOption(id: "storm", label: "A Storm"),
            ParameterOption(id: "tivoli", label: "The Cascades at Tivoli"),
        ]
    }
}

/// Answers "a" after "ab", like a short `brew search` query overtaken by a refined one
/// whose details were cached.
private actor OutOfOrderOptionsModule: Module {
    let id = "outOfOrder"
    let displayName = "Out of Order"
    let iconName = "sparkle"
    var isEnabled = true

    func initialize(context _: ModuleContext) async throws {}

    func provideActions(query _: String, scoring _: ScoringContext) async -> [any Action] {
        []
    }

    func provideParameterOptions(for _: String, in _: ActionID, query: String) async -> [ParameterOption] {
        if query == "a" {
            try? await Task.sleep(for: .milliseconds(500))
        }
        return [ParameterOption(id: query, label: query)]
    }
}
