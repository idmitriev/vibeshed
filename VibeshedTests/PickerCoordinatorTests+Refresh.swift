@testable import Vibeshed
import XCTest

/// A refresh re-ranks the list for the same text: a module reporting new actions, or the
/// picker re-shown with its state. The 2026-10-13 report: "pr" listed an upcoming
/// meeting first, ↓ moved to Search Pull Requests, and a refresh moments later put the
/// highlight back on the meeting, so Return opened its Zoom link.
extension PickerCoordinatorTests {
    func testRefreshKeepsTheHighlightedRow() async throws {
        let (coordinator, state) = try await makeCoordinator(module: ReshufflingCatalogModule())
        coordinator.start()
        state.query = "pr"
        try await waitForTitles(["Pairing session", "Search Pull Requests", "Pull Request Reviews"], in: state)
        state.selectNext()
        XCTAssertEqual(state.selectedActionID, ReshufflingCatalogModule.searchPullRequests)

        await coordinator.refreshActions()

        XCTAssertEqual(
            state.actions.map(\.title), ["Pairing session", "Pull Request Reviews", "Search Pull Requests"],
            "the refresh reordered the rows"
        )
        XCTAssertEqual(state.selectedActionID, ReshufflingCatalogModule.searchPullRequests)
    }

    func testNewQueryAfterARefreshStartsOnTheFirstRow() async throws {
        let (coordinator, state) = try await makeCoordinator(module: ReshufflingCatalogModule())
        coordinator.start()
        state.query = "pr"
        try await waitForTitles(["Pairing session", "Search Pull Requests", "Pull Request Reviews"], in: state)
        state.selectNext()
        await coordinator.refreshActions()

        // Typing re-scores the refreshed catalog, so Reviews still leads.
        state.query = "pull"
        try await waitForTitles(["Pull Request Reviews", "Search Pull Requests"], in: state)

        XCTAssertEqual(state.selectedActionID, ReshufflingCatalogModule.pullRequestReviews)
    }
}

/// An event starting in four minutes, which ranks first for any query it matches, and two
/// rows whose order flips on every fetch — as when modules answer the catalog fan-out in
/// a different order, or a clock-driven score moves.
private actor ReshufflingCatalogModule: Module {
    static let pairing = ActionID(module: "reshuffling", name: "event.pairing")
    static let searchPullRequests = ActionID(module: "reshuffling", name: "searchPullRequests")
    static let pullRequestReviews = ActionID(module: "reshuffling", name: "pullRequestReviews")

    let id = "reshuffling"
    let displayName = "Reshuffling Catalog"
    let iconName = "shuffle"
    var isEnabled = true
    private var fetches = 0

    func initialize(context _: ModuleContext) async throws {}

    func provideActions(query _: String, scoring _: ScoringContext) async -> [any Action] {
        fetches += 1
        let start = Date().addingTimeInterval(4 * 60)
        let event = CalendarAction(
            id: Self.pairing,
            title: "Pairing session",
            subtitle: "",
            startDate: start,
            endDate: start.addingTimeInterval(30 * 60),
            videoLinkType: .zoom,
            videoURL: URL(string: "https://zoom.us/j/123456789")
        ) { _ in .dismiss }
        let searchFirst = fetches.isMultiple(of: 2) == false
        let rows = [
            MockAction(
                id: Self.searchPullRequests, title: "Search Pull Requests", subtitle: "", iconName: nil,
                relevanceScore: searchFirst ? 0.9 : 0.1, keywords: []
            ),
            MockAction(
                id: Self.pullRequestReviews, title: "Pull Request Reviews", subtitle: "", iconName: nil,
                relevanceScore: searchFirst ? 0.1 : 0.9, keywords: []
            ),
        ]
        return [event] + rows
    }
}
