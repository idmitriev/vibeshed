@testable import Vibeshed
import XCTest

private struct StubAction: Action {
    let id: ActionID
    let title: String
    var subtitle: String = ""
    var iconName: String?
    var relevanceScore: Double = 0.5
    var keywords: [String] = []
    var parameters: [ActionParameter] = []
    var scheduledStart: Date?
    var scheduledEnd: Date?
    func run(with _: ParameterValues) async throws -> ActionResult {
        .dismiss
    }
}

final class ActionScorerTests: XCTestCase {
    private func scoring(_ query: String, now: Date = Date()) -> ScoringContext {
        ScoringContext(
            usageCounts: [:], lastUsedDates: [:], query: query,
            systemContext: nil, now: now
        )
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
        XCTAssertEqual(items.map(\.id.actionName), ["high", "mid", "low"])
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
        XCTAssertEqual(items.map(\.id.actionName), ["settings"])
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

    func testDeduplicationKeyDefaultsToNil() {
        let action = StubAction(id: ActionID("m/x"), title: "X")
        XCTAssertNil(action.deduplicationKey)
    }

    func testURLActionsExposeNormalizedDedupKey() {
        let tab = BrowserAction(
            id: ActionID("browser/t"), title: "T", subtitle: "",
            tabURL: "https://Example.com/Path/"
        ) { _ in .dismiss }
        let bookmark = BookmarkAction(
            id: ActionID("bookmark/b"), title: "B", subtitle: "",
            url: "https://example.com/path"
        ) { _ in .dismiss }
        // Both normalize to the same key, which is what drives cross-source dedup.
        XCTAssertEqual(tab.deduplicationKey, "https://example.com/path")
        XCTAssertEqual(tab.deduplicationKey, bookmark.deduplicationKey)
    }

    func testActionsWithDistinctKeysAreNotDeduped() {
        let first = BrowserAction(
            id: ActionID("browser/a"), title: "A", subtitle: "",
            relevanceScore: 0.8, tabURL: "https://a.com"
        ) { _ in .dismiss }
        let second = BrowserAction(
            id: ActionID("browser/b"), title: "B", subtitle: "",
            relevanceScore: 0.7, tabURL: "https://b.com"
        ) { _ in .dismiss }
        let (items, _) = ActionScorer.scoreAndRank(
            allActions: [first, second], enrichments: [:], query: "", scoring: scoring("")
        )
        XCTAssertEqual(items.count, 2)
    }

    func testImminentEventOutranksAStrongerTextMatch() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let start = now.addingTimeInterval(3 * 60)
        // "standup" matches the exact title of the non-event action and only fuzzily
        // (s-t-a-n-d-u-p scattered) the event's — yet the event must still win.
        let exactMatch = StubAction(
            id: ActionID("m/standup"), title: "Standup", relevanceScore: 0.9
        )
        let event = StubAction(
            id: ActionID("calendar/event.x"), title: "Sprint Team Sync and Updates Prep",
            relevanceScore: 0.9,
            scheduledStart: start, scheduledEnd: start.addingTimeInterval(1800)
        )
        let (items, _) = ActionScorer.scoreAndRank(
            allActions: [exactMatch, event], enrichments: [:],
            query: "standup", scoring: scoring("standup", now: now)
        )
        XCTAssertEqual(items.map(\.id.actionName), ["event.x", "standup"])
    }

    func testDistantEventDoesNotOutrankAStrongerTextMatch() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let start = now.addingTimeInterval(8 * 3600)
        let exactMatch = StubAction(
            id: ActionID("m/standup"), title: "Standup", relevanceScore: 0.9
        )
        let event = StubAction(
            id: ActionID("calendar/event.x"), title: "Sprint Team Sync and Updates Prep",
            relevanceScore: 0.9,
            scheduledStart: start, scheduledEnd: start.addingTimeInterval(1800)
        )
        let (items, _) = ActionScorer.scoreAndRank(
            allActions: [exactMatch, event], enrichments: [:],
            query: "standup", scoring: scoring("standup", now: now)
        )
        XCTAssertEqual(items.map(\.id.actionName), ["standup", "event.x"])
    }

    func testEventsRankByHowSoonTheyStart() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func event(_ name: String, inMinutes: Double) -> StubAction {
            let start = now.addingTimeInterval(inMinutes * 60)
            return StubAction(
                id: ActionID("calendar/\(name)"), title: "Meeting \(name)",
                relevanceScore: 0.5,
                scheduledStart: start, scheduledEnd: start.addingTimeInterval(1800)
            )
        }
        let actions: [any Action] = [
            event("later", inMinutes: 90),
            event("soon", inMinutes: 2),
            event("mid", inMinutes: 30),
        ]
        let (items, _) = ActionScorer.scoreAndRank(
            allActions: actions, enrichments: [:],
            query: "meeting", scoring: scoring("meeting", now: now)
        )
        XCTAssertEqual(items.map(\.id.actionName), ["soon", "mid", "later"])
    }

    func testNormalizeURL() {
        XCTAssertEqual(ActionScorer.normalizeURL("https://A.com/Path/"), "https://a.com/path")
        XCTAssertEqual(ActionScorer.normalizeURL("https://x.com/#frag"), "https://x.com")
        XCTAssertEqual(ActionScorer.normalizeURL("https://x.com///"), "https://x.com")
    }
}
