@testable import Vibeshed
import XCTest

/// `FuzzyMatcher.match` scores the best in-order alignment of the query by where its
/// chunks start (text start, word start, inside a word, scattered), normalized to
/// 0...1. These tests pin the behavioral contract — exact anchors where the value is
/// well-defined, and ordering properties for the heuristics.
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

    func testSubsequenceMatchScoresWithinRange() throws {
        let result = FuzzyMatcher.match(query: "ac", against: "abc")
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(try XCTUnwrap(result?.score), 0)
        XCTAssertLessThanOrEqual(try XCTUnwrap(result?.score), 1)
    }

    func testMatchIsCaseInsensitive() {
        XCTAssertNotNil(FuzzyMatcher.match(query: "ABC", against: "abc"))
    }

    func testStartOfStringScoresHigherThanLaterMatch() throws {
        let atStart = try XCTUnwrap(FuzzyMatcher.match(query: "a", against: "abc")?.score)
        let later = try XCTUnwrap(FuzzyMatcher.match(query: "c", against: "abc")?.score)
        XCTAssertGreaterThan(atStart, later)
    }

    func testWordBoundaryScoresHigherThanMidWord() throws {
        let boundary = try XCTUnwrap(FuzzyMatcher.match(query: "w", against: "a-w")?.score)
        let midWord = try XCTUnwrap(FuzzyMatcher.match(query: "w", against: "aaw")?.score)
        XCTAssertGreaterThan(boundary, midWord)
    }

    func testExactMatchScoresOne() {
        XCTAssertEqual(FuzzyMatcher.match(query: "spotify", against: "Spotify")?.score ?? -1, 1, accuracy: acc)
    }

    /// The best placement wins, not the leftmost: "theme" is the word in "Switch Theme…",
    /// not the t…h of "Switch" — so it scores as the word does in "Reapply Theme".
    func testFindsTheBestAlignmentNotTheLeftmost() throws {
        let title = "Switch Theme…"
        let result = try XCTUnwrap(FuzzyMatcher.match(query: "theme", against: title))
        XCTAssertEqual(result.matchedRanges.map { String(title[$0]) }, ["Theme"])
        let reapply = try XCTUnwrap(FuzzyMatcher.match(query: "theme", against: "Reapply Theme")?.score)
        XCTAssertEqual(result.score, reapply, accuracy: acc)
    }

    /// The start of the text beats a later word, which beats an initialism, which beats
    /// a substring inside a word.
    func testMatchClassesRankInOrder() throws {
        func score(_ query: String, _ target: String) throws -> Double {
            try XCTUnwrap(FuzzyMatcher.match(query: query, against: target)?.score)
        }
        let start = try score("spot", "Spotify")
        let laterWord = try score("spot", "Siri & Spotlight")
        let initials = try score("spsl", "Siri & Spotlight Settings List")
        let inWord = try score("pot", "Spotify")
        XCTAssertGreaterThan(start, laterWord)
        XCTAssertGreaterThan(laterWord, initials)
        XCTAssertGreaterThan(initials, inWord)
    }

    /// Letters picked up inside a word after a skip are coincidence: "mind" scattered
    /// through "Minimize Window" or "Minimized" loses to "mind" as a word, and "pr"
    /// scattered in "Pairing" loses to the initials of "Pull Requests".
    func testScatteredHitsLoseToWordMatches() throws {
        func score(_ query: String, _ target: String) throws -> Double {
            try XCTUnwrap(FuzzyMatcher.match(query: query, against: target)?.score)
        }
        let word = try score("mind", "teach the picker to read my mind")
        XCTAssertGreaterThan(word, try score("mind", "Minimize Window"))
        XCTAssertGreaterThan(word, try score("mind", "Restore Minimized Windows"))
        XCTAssertGreaterThan(try score("pr", "Search Pull Requests"), try score("pr", "Pairing session"))
    }

    /// Punctuation and a capital after a lowercase letter start words.
    func testWordStarts() throws {
        func score(_ query: String, _ target: String) throws -> Double {
            try XCTUnwrap(FuzzyMatcher.match(query: query, against: target)?.score)
        }
        XCTAssertEqual(
            try score("restore", "Toggle Maximize/Restore"), try score("restore", "Toggle Maximize Restore"),
            accuracy: acc
        )
        XCTAssertGreaterThan(try score("hub", "GitHub"), try score("hub", "Github"))
        XCTAssertEqual(
            try score("spot", "Siri & Spotlight"), try score("spot", "Siri a Spotlight"), accuracy: acc
        )
    }

    /// Of titles holding the same word, the shorter one wins.
    func testShorterTitleBreaksTies() throws {
        let short = try XCTUnwrap(FuzzyMatcher.match(query: "grid", against: "Attach Window to Grid")?.score)
        let long = try XCTUnwrap(FuzzyMatcher.match(query: "grid", against: "Attach All Windows to Grid")?.score)
        XCTAssertGreaterThan(short, long)
    }

    func testHighlightsInitials() throws {
        let title = "Search Pull Requests"
        let result = try XCTUnwrap(FuzzyMatcher.match(query: "pr", against: title))
        XCTAssertEqual(result.matchedRanges.map { String(title[$0]) }, ["P", "R"])
    }

    // MARK: - score()

    func testScoreEmptyQueryUsesRelevanceAndUsage() {
        let result = FuzzyMatcher.score(
            query: "", target: .init(title: "t", subtitle: "s", keywords: [], relevanceScore: 0.5),
            usageBoost: 0.2
        )
        // relevanceScore * 0.4 + usageBoost * 0.6
        XCTAssertEqual(result?.score ?? -1, 0.32, accuracy: acc)
        XCTAssertEqual(result?.titleRanges.count, 0)
    }

    func testScoreKeywordOnlyMatch() {
        let exact = FuzzyMatcher.score(
            query: "kw", target: .init(title: "x", subtitle: "y", keywords: ["kw"], relevanceScore: 0),
            usageBoost: 0
        )
        let prefix = FuzzyMatcher.score(
            query: "kw", target: .init(title: "x", subtitle: "y", keywords: ["kwd"], relevanceScore: 0),
            usageBoost: 0
        )
        // Only the keyword bonus contributes: an exact keyword counts as an exact title
        // (the title weight), a prefix much less.
        XCTAssertEqual(exact?.score ?? -1, 0.4, accuracy: acc)
        XCTAssertEqual(prefix?.score ?? -1, 0.1, accuracy: acc)
        XCTAssertEqual(exact?.titleRanges.count, 0)
    }

    func testScoreReturnsNilWhenNothingMatches() {
        let result = FuzzyMatcher.score(
            query: "zzz", target: .init(title: "a", subtitle: "b", keywords: ["c"], relevanceScore: 0),
            usageBoost: 0
        )
        XCTAssertNil(result)
    }

    func testScoreTitleMatchPopulatesRanges() {
        let result = FuzzyMatcher.score(
            query: "set", target: .init(title: "settings", subtitle: "", keywords: [], relevanceScore: 0),
            usageBoost: 0
        )
        XCTAssertNotNil(result)
        XCTAssertFalse(result?.titleRanges.isEmpty ?? true)
        XCTAssertGreaterThan(result?.score ?? -1, 0)
    }

    func testScoreIncreasesWithUsageBoost() {
        func score(usage: Double) -> Double {
            FuzzyMatcher.score(
                query: "set", target: .init(title: "settings", subtitle: "", keywords: [], relevanceScore: 0),
                usageBoost: usage
            )!.score
        }
        XCTAssertGreaterThan(score(usage: 0.5), score(usage: 0.0))
    }
}
