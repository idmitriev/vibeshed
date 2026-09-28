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
