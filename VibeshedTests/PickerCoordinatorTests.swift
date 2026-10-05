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

    // MARK: - Typing right after a fresh open

    /// What `PanelController.show` does on a fresh open, up to the show animation.
    private func openFresh(_ coordinator: PickerCoordinator, _ state: PickerState) {
        state.reset()
        coordinator.clearContext()
        coordinator.showCachedActionsIfAvailable()
    }

    /// Opens, settles on `query`, and leaves the picker the way Escape or a click
    /// outside does: hidden with the text still in the field, so the debounced
    /// pipeline never sees it go back to "".
    private func settlePreviousSession(
        on query: String,
        _ coordinator: PickerCoordinator,
        _ state: PickerState
    ) async throws {
        await coordinator.loadInitialActions().value // fills the empty-query cache
        state.query = query
        try await Task.sleep(for: .milliseconds(300)) // past the debounce
        XCTAssertEqual(state.actions.map(\.title), ["Safari"])
    }

    /// The 2026-10-04 report: "safari" typed right after opening, while the list kept
    /// showing the results for "s" (Screenshot first) and Return ran Screenshot. The
    /// show animation's initial load caught "s" and its catalog refetch landed last;
    /// the debounced "safari" was dropped as a repeat of the previous session's.
    func testTypingOverTheInitialLoadEndsOnTheFieldsResults() async throws {
        let module = SlowCatalogModule()
        let (coordinator, state) = try await makeCoordinator(module: module)
        coordinator.start()
        try await settlePreviousSession(on: "safari", coordinator, state)

        await module.setDelay(.milliseconds(500))
        openFresh(coordinator, state)
        state.query = "s" // typed during the show animation, within the debounce of the reset
        coordinator.loadInitialActions()
        for text in ["sa", "saf", "safa", "safar", "safari"] {
            try await Task.sleep(for: .milliseconds(20)) // the first one lets the initial load read "s"
            state.query = text
        }
        try await Task.sleep(for: .milliseconds(900)) // the debounce, then the slow refetch landing

        XCTAssertEqual(state.query, "safari")
        XCTAssertEqual(state.actions.map(\.title), ["Safari"])
        XCTAssertEqual(state.selectedActionID, SlowCatalogModule.safari)
    }

    /// Reopening with the previous session's text (`vibeshed://picker?q=` again) ranks
    /// it with the cached catalog, instead of leaving the cached empty-query list up
    /// until the initial load's refetch lands.
    func testReopeningWithThePreviousQueryRanksItRightAway() async throws {
        let module = SlowCatalogModule()
        let (coordinator, state) = try await makeCoordinator(module: module)
        coordinator.start()
        try await settlePreviousSession(on: "safari", coordinator, state)

        openFresh(coordinator, state)
        XCTAssertEqual(state.actions.first?.title, "Screenshot (Interactive)", "the cached empty-query list")
        state.query = "safari" // URIManager sets it right after show()
        try await Task.sleep(for: .milliseconds(400)) // past the debounce; no initial load runs here

        XCTAssertEqual(state.actions.map(\.title), ["Safari"])
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

/// The rows from the report: "s" matches all of them, "safari" only Safari. The
/// catalog can be slowed down like the refetch on a busy machine.
private actor SlowCatalogModule: Module {
    static let safari = ActionID(module: "slow", name: "safari")

    let id = "slow"
    let displayName = "Slow Catalog"
    let iconName = "tortoise"
    var isEnabled = true
    private var delay: Duration = .zero

    func initialize(context _: ModuleContext) async throws {}

    func setDelay(_ delay: Duration) {
        self.delay = delay
    }

    func provideActions(query _: String, scoring _: ScoringContext) async -> [any Action] {
        try? await Task.sleep(for: delay)
        let titles = ["Screenshot (Interactive)", "Sleep", "Shrink Width", "Shrink Height", "Lock Screen"]
        let rows = titles.enumerated().map { index, title in
            MockAction(
                id: ActionID(module: id, name: "row\(index)"),
                title: title,
                subtitle: "",
                iconName: nil,
                relevanceScore: 1 - Double(index) * 0.1,
                keywords: []
            )
        }
        let safari = MockAction(
            id: Self.safari, title: "Safari", subtitle: "", iconName: nil, relevanceScore: 0.3, keywords: []
        )
        return rows + [safari]
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
