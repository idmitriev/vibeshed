import XCTest

@testable import Vibeshed

private struct StubAction: Action {
    let id: ActionID
    let title: String
    var subtitle: String = ""
    var iconName: String?
    var relevanceScore: Double = 0.5
    var keywords: [String] = []
    var parameters: [ActionParameter] = []
    func run(with _: ParameterValues) async throws -> ActionResult { .dismiss }
}

final class ActionScorerTests: XCTestCase {
    private func scoring(_ query: String) -> ScoringContext {
        ScoringContext(usageCounts: [:], lastUsedDates: [:], query: query, systemContext: nil)
    }

    func testEmptyQuerySortsByRelevanceDescending() {
        let actions: [any Action] = [
            StubAction(id: ActionID("m/low"), title: "Low", relevanceScore: 0.2),
            StubAction(id: ActionID("m/high"), title: "High", relevanceScore: 0.9),
            StubAction(id: ActionID("m/mid"), title: "Mid", relevanceScore: 0.5),
        ]
        let (items, cache) = ActionScorer.scoreAndRank(
            allActions: actions, enrichments: [:], query: "", scoring: scoring("")
        )
        XCTAssertEqual(items.map { $0.id.actionName }, ["high", "mid", "low"])
        XCTAssertEqual(cache.count, 3)
    }

    func testNonMatchingActionsDroppedForNonEmptyQuery() {
        let actions: [any Action] = [
            StubAction(id: ActionID("m/settings"), title: "Settings"),
            StubAction(id: ActionID("m/zzz"), title: "Nothing"),
        ]
        let (items, _) = ActionScorer.scoreAndRank(
            allActions: actions, enrichments: [:], query: "set", scoring: scoring("set")
        )
        XCTAssertEqual(items.map { $0.id.actionName }, ["settings"])
    }

    func testEnrichmentEnablesKeywordMatch() {
        let action = StubAction(id: ActionID("m/x"), title: "Open Mail")
        // "compose" matches only via the alias-provided keyword enrichment.
        let withoutEnrichment = ActionScorer.scoreAndRank(
            allActions: [action], enrichments: [:], query: "compose", scoring: scoring("compose")
        )
        XCTAssertTrue(withoutEnrichment.0.isEmpty)

        let withEnrichment = ActionScorer.scoreAndRank(
            allActions: [action], enrichments: [ActionID("m/x"): ["compose"]],
            query: "compose", scoring: scoring("compose")
        )
        XCTAssertEqual(withEnrichment.0.count, 1)
        XCTAssertTrue(withEnrichment.0[0].keywords.contains("compose"))
    }

    func testBrowserTabWinsOverBookmarkForSameURL() {
        let tab = BrowserAction(
            id: ActionID("browser/tab.1"), title: "GitHub", subtitle: "",
            relevanceScore: 0.8, tabURL: "https://github.com/"
        ) { _ in .dismiss }
        let bookmark = BookmarkAction(
            id: ActionID("bookmark/bm.1"), title: "GitHub", subtitle: "",
            relevanceScore: 0.6, url: "https://github.com"
        ) { _ in .dismiss }

        let (items, _) = ActionScorer.scoreAndRank(
            allActions: [bookmark, tab], enrichments: [:], query: "", scoring: scoring("")
        )
        // Dedup drops the lower-scored bookmark from the visible list; the higher-scored
        // tab wins. (The cache deliberately isn't pruned on dedup — only the 200-cap is —
        // so a stale cache entry for the dropped item is expected, matching prior behavior.)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.id, ActionID("browser/tab.1"))
    }

    func testResultsCappedAndCachePruned() {
        let actions: [any Action] = (0 ..< 250).map {
            StubAction(id: ActionID("m/a\($0)"), title: "Item \($0)", relevanceScore: 0.5)
        }
        let (items, cache) = ActionScorer.scoreAndRank(
            allActions: actions, enrichments: [:], query: "", scoring: scoring("")
        )
        XCTAssertEqual(items.count, 200)
        XCTAssertEqual(cache.count, 200)
    }

    func testNormalizeURL() {
        XCTAssertEqual(ActionScorer.normalizeURL("https://A.com/Path/"), "https://a.com/path")
        XCTAssertEqual(ActionScorer.normalizeURL("https://x.com/#frag"), "https://x.com")
        XCTAssertEqual(ActionScorer.normalizeURL("https://x.com///"), "https://x.com")
    }
}
