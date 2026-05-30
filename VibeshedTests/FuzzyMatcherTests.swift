import XCTest

@testable import Vibeshed

/// `FuzzyMatcher.match` is a single normalized subsequence scorer (start-of-string,
/// word-boundary, and consecutive bonuses, then normalized to 0...1). These tests
/// pin the behavioral contract — exact anchors where the value is well-defined, and
/// ordering properties for the bonus heuristics.
final class FuzzyMatcherTests: XCTestCase {
    private let acc = 0.0001

    // MARK: - match()

    func testEmptyQueryScoresPerfectWithNoRanges() {
        let result = FuzzyMatcher.match(query: "", against: "anything")
        XCTAssertEqual(result?.score, 1.0)
        XCTAssertEqual(result?.matchedRanges.count, 0)
    }

    func testNoMatchWhenQueryCharAbsent() {
        XCTAssertNil(FuzzyMatcher.match(query: "xyz", against: "abc"))
    }

    func testMatchRequiresInOrderSubsequence() {
        // "ba" is not a subsequence of "abc" ('a' only precedes 'b').
        XCTAssertNil(FuzzyMatcher.match(query: "ba", against: "abc"))
    }

    func testSubsequenceMatchScoresWithinRange() {
        let result = FuzzyMatcher.match(query: "ac", against: "abc")
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result!.score, 0)
        XCTAssertLessThanOrEqual(result!.score, 1)
    }

    func testMatchIsCaseInsensitive() {
        XCTAssertNotNil(FuzzyMatcher.match(query: "ABC", against: "abc"))
    }

    func testStartOfStringScoresHigherThanLaterMatch() {
        let atStart = FuzzyMatcher.match(query: "a", against: "abc")!.score
        let later = FuzzyMatcher.match(query: "c", against: "abc")!.score
        XCTAssertGreaterThan(atStart, later)
    }

    func testWordBoundaryScoresHigherThanMidWord() {
        let boundary = FuzzyMatcher.match(query: "w", against: "a-w")!.score
        let midWord = FuzzyMatcher.match(query: "w", against: "aaw")!.score
        XCTAssertGreaterThan(boundary, midWord)
    }

    // MARK: - score()

    func testScoreEmptyQueryUsesRelevanceAndUsage() {
        let result = FuzzyMatcher.score(
            query: "", title: "t", subtitle: "s", keywords: [],
            relevanceScore: 0.5, usageBoost: 0.2
        )
        // relevanceScore * 0.4 + usageBoost * 0.6
        XCTAssertEqual(result?.score ?? -1, 0.32, accuracy: acc)
        XCTAssertEqual(result?.titleRanges.count, 0)
    }

    func testScoreKeywordOnlyMatch() {
        let result = FuzzyMatcher.score(
            query: "kw", title: "x", subtitle: "y", keywords: ["kw"],
            relevanceScore: 0, usageBoost: 0
        )
        // Only the keyword bonus contributes.
        XCTAssertEqual(result?.score ?? -1, 0.1, accuracy: acc)
        XCTAssertEqual(result?.titleRanges.count, 0)
    }

    func testScoreReturnsNilWhenNothingMatches() {
        let result = FuzzyMatcher.score(
            query: "zzz", title: "a", subtitle: "b", keywords: ["c"],
            relevanceScore: 0, usageBoost: 0
        )
        XCTAssertNil(result)
    }

    func testScoreTitleMatchPopulatesRanges() {
        let result = FuzzyMatcher.score(
            query: "set", title: "settings", subtitle: "", keywords: [],
            relevanceScore: 0, usageBoost: 0
        )
        XCTAssertNotNil(result)
        XCTAssertFalse(result?.titleRanges.isEmpty ?? true)
        XCTAssertGreaterThan(result?.score ?? -1, 0)
    }

    func testScoreIncreasesWithUsageBoost() {
        func score(usage: Double) -> Double {
            FuzzyMatcher.score(
                query: "set", title: "settings", subtitle: "", keywords: [],
                relevanceScore: 0, usageBoost: usage
            )!.score
        }
        XCTAssertGreaterThan(score(usage: 0.5), score(usage: 0.0))
    }
}
