import Foundation

/// Scores how well a typed query matches an action's title, subtitle and keywords.
///
/// Titles and subtitles are matched by `align` (FuzzyMatcher+Alignment): the query
/// must appear in order, and the best placement wins rather than the leftmost one,
/// so "theme" lands on the word in "Switch Theme…" instead of the t…h in "Switch".
/// A match that starts the text beats one that starts a later word, which beats one
/// inside a word; letters picked up inside a word after a skip count against it.
enum FuzzyMatcher {
    struct MatchResult {
        let score: Double
        let matchedRanges: [Range<String.Index>]
    }

    /// How a typed query's terms add up (see `score`).
    enum Weight {
        static let title = 0.4
        static let subtitle = 0.1
        /// A keyword equal to the query is a deliberate synonym ("car" on 🚗
        /// Automobile), so it counts as much as an exact title — more than any partial
        /// title match. A keyword the query only starts is a weaker hint.
        static let exactKeyword = title
        static let keywordPrefix = 0.1
        static let relevance = 0.15
        /// Usage of an action under any query only breaks ties between comparable
        /// matches. What the user picks after typing a given query is the stronger
        /// signal, applied by `ActionScorer` (see `QueryHistory`).
        static let usage = 0.05
        /// With nothing typed the list is a launchpad: usage leads, relevance follows.
        static let emptyQueryRelevance = 0.4
        static let emptyQueryUsage = 0.6
    }

    /// Fuzzy match a query against a target string.
    /// Returns nil if the query cannot be matched, otherwise returns a score (0..1) and highlight ranges.
    static func match(query: String, against target: String) -> MatchResult? {
        match(Query(query), against: SearchText(target))
    }

    /// Core matcher over precomputed forms. The per-keystroke scoring path builds the
    /// `SearchText`s once per action (see `ScorableAction`).
    static func match(_ query: Query, against text: SearchText) -> MatchResult? {
        guard let alignment = align(query.codes, in: text, wantIndices: true) else { return nil }
        return MatchResult(
            score: alignment.quality,
            matchedRanges: buildRanges(from: alignment.indices, in: text.original)
        )
    }

    /// Precomputed searchable forms of one action's fields. Built once per action
    /// when the corpus is (re)fetched so per-keystroke scoring does no string work.
    struct ScoreTarget: Sendable {
        let title: SearchText
        let subtitle: SearchText
        let keywordsLower: [String]
        let relevanceScore: Double

        init(title: String, subtitle: String, keywords: [String], relevanceScore: Double) {
            self.title = SearchText(title)
            self.subtitle = SearchText(subtitle)
            self.keywordsLower = keywords.map { $0.lowercased() }
            self.relevanceScore = relevanceScore
        }
    }

    /// Score an action against a query, combining fuzzy match with module score and usage.
    /// Returns nil if the action doesn't match at all.
    static func score(
        query: String,
        target: ScoreTarget,
        usageBoost: Double
    ) -> (score: Double, titleRanges: [Range<String.Index>])? {
        score(Query(query), target: target, usageBoost: usageBoost)
    }

    /// Precomputed-input variant of `score` — the per-keystroke hot path.
    static func score(
        _ query: Query,
        target: ScoreTarget,
        usageBoost: Double
    ) -> (score: Double, titleRanges: [Range<String.Index>])? {
        guard !query.isEmpty else {
            // No query: score based on relevance and usage only
            let score = target.relevanceScore * Weight.emptyQueryRelevance + usageBoost * Weight.emptyQueryUsage
            return (score: score, titleRanges: [])
        }

        let titleMatch = match(query, against: target.title)
        // Subtitles aren't highlighted, so skip tracing the alignment.
        let subtitleScore = align(query.codes, in: target.subtitle, wantIndices: false)?.quality
        let keywordBonus: Double = if target.keywordsLower.contains(query.lowered) {
            Weight.exactKeyword
        } else if target.keywordsLower.contains(where: { $0.hasPrefix(query.lowered) }) {
            Weight.keywordPrefix
        } else {
            0
        }

        // Must match at least title, subtitle, or keyword
        guard titleMatch != nil || subtitleScore != nil || keywordBonus > 0 else {
            return nil
        }

        let combined = (titleMatch?.score ?? 0) * Weight.title
            + (subtitleScore ?? 0) * Weight.subtitle
            + keywordBonus
            + target.relevanceScore * Weight.relevance
            + usageBoost * Weight.usage

        return (
            score: combined,
            titleRanges: titleMatch?.matchedRanges ?? []
        )
    }

    // MARK: - Private

    private static func buildRanges(from indices: [Int], in string: String) -> [Range<String.Index>] {
        guard let lastIndex = indices.last, !indices.isEmpty else { return [] }
        guard lastIndex < string.count else { return [] }

        var ranges: [Range<String.Index>] = []
        var currentIdx = string.startIndex
        var currentInt = 0

        /// Advance currentIdx to the given int position
        func advance(to target: Int) -> String.Index {
            while currentInt < target {
                currentIdx = string.index(after: currentIdx)
                currentInt += 1
            }
            return currentIdx
        }

        var rangeStartInt = indices[0]
        var rangeEndInt = indices[0]

        for index in indices.dropFirst() {
            if index == rangeEndInt + 1 {
                rangeEndInt = index
            } else {
                let start = advance(to: rangeStartInt)
                let end = advance(to: rangeEndInt + 1)
                ranges.append(start ..< end)
                rangeStartInt = index
                rangeEndInt = index
            }
        }

        let start = advance(to: rangeStartInt)
        let end = advance(to: rangeEndInt + 1)
        ranges.append(start ..< end)

        return ranges
    }
}
