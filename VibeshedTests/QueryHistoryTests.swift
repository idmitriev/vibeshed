@testable import Vibeshed
import XCTest

final class QueryHistoryTests: XCTestCase {
    private let acc = 0.0001
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func history(_ picks: [(query: String, action: String)], at date: Date? = nil) -> QueryHistory {
        var history = QueryHistory()
        for pick in picks {
            history.record(query: pick.query, actionID: pick.action, at: date ?? now)
        }
        return history
    }

    func testOnePickIsHalfTheShare() {
        let shares = history([("theme", "theme/switch")]).shares(for: "theme", now: now)
        XCTAssertEqual(shares["theme/switch"] ?? -1, 0.5, accuracy: acc)
    }

    func testRepeatedPicksOutweighAStrayOne() {
        let shares = history([
            ("grid", "tiling/attachAll"), ("grid", "tiling/attachAll"), ("grid", "tiling/attachAll"),
            ("grid", "tiling/attach"),
        ]).shares(for: "grid", now: now)
        XCTAssertEqual(shares["tiling/attachAll"] ?? -1, 3.0 / 5, accuracy: acc)
        XCTAssertEqual(shares["tiling/attach"] ?? -1, 1.0 / 5, accuracy: acc)
    }

    /// Typing the start of an earlier query counts fully; typing past one counts by the
    /// fraction typed then; an unrelated query counts not at all.
    func testRelatedQueries() {
        let shortPick = history([("th", "theme/switch")])
        let longPick = history([("theme", "theme/switch")])
        XCTAssertEqual(longPick.shares(for: "th", now: now)["theme/switch"] ?? -1, 0.5, accuracy: acc)
        XCTAssertEqual(shortPick.shares(for: "theme", now: now)["theme/switch"] ?? -1, 0.4 / 1.4, accuracy: acc)
        XCTAssertTrue(longPick.shares(for: "mind", now: now).isEmpty)
        XCTAssertTrue(longPick.shares(for: "", now: now).isEmpty, "an empty query ranks by usage alone")
    }

    func testPicksHalveEveryHalfLife() {
        let old = history([("pr", "github/searchPRs")], at: now.addingTimeInterval(-QueryHistory.halfLife))
        XCTAssertEqual(old.shares(for: "pr", now: now)["github/searchPRs"] ?? -1, 0.5 / 1.5, accuracy: acc)
    }

    func testQueriesAreNormalized() {
        let history = history([("  Theme ", "theme/switch"), ("", "theme/next")])
        XCTAssertEqual(history.picks.keys.sorted(), ["theme/switch"])
        XCTAssertEqual(history.picks["theme/switch"]?.keys.sorted(), ["theme"])
        let long = String(repeating: "x", count: 100)
        XCTAssertEqual(QueryHistory.normalize(long)?.count, QueryHistory.maxQueryLength)
    }

    func testKeepsTheStrongestQueriesPerAction() {
        var history = QueryHistory()
        history.record(query: "keep", actionID: "m/a", at: now)
        history.record(query: "keep", actionID: "m/a", at: now)
        for index in 0 ..< QueryHistory.queriesPerAction {
            history.record(query: "q\(index)", actionID: "m/a", at: now.addingTimeInterval(Double(index)))
        }
        let kept = history.picks["m/a"] ?? [:]
        XCTAssertEqual(kept.count, QueryHistory.queriesPerAction)
        XCTAssertNotNil(kept["keep"])
        XCTAssertNil(kept["q0"], "the faintest single pick goes first")
    }

    func testPruningDropsFadedPicks() {
        var history = history([("old", "m/old")], at: now.addingTimeInterval(-10 * QueryHistory.halfLife))
        history.record(query: "new", actionID: "m/new", at: now)
        XCTAssertEqual(history.pruned(at: now).picks.keys.sorted(), ["m/new"])
    }
}
