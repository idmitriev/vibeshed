import Foundation

enum FuzzyMatcher {
    struct MatchResult {
        let score: Double
        let matchedRanges: [Range<String.Index>]
    }

    /// Fuzzy match a query against a target string.
    /// Returns nil if the query cannot be matched, otherwise returns a score (0..1) and highlight ranges.
    static func match(query: String, against target: String) -> MatchResult? {
        match(
            queryChars: Array(query.lowercased()),
            against: Array(target.lowercased()),
            original: target
        )
    }

    /// Core matcher over pre-lowercased character arrays. The per-keystroke scoring
    /// path precomputes these once per action (see `ScorableAction`) instead of
    /// re-lowercasing every title/subtitle/keyword on each keystroke.
    /// `original` is the un-lowercased target, used to build highlight ranges.
    static func match(
        queryChars: [Character],
        against targetChars: [Character],
        original: String
    ) -> MatchResult? {
        guard !queryChars.isEmpty else {
            return MatchResult(score: 1.0, matchedRanges: [])
        }
        guard !targetChars.isEmpty else { return nil }

        var qIdx = 0
        var matchedIndices: [Int] = []
        var totalScore: Double = 0

        for (tIdx, tChar) in targetChars.enumerated() {
            guard qIdx < queryChars.count else { break }
            if tChar == queryChars[qIdx] {
                matchedIndices.append(tIdx)

                // Bonus: match at start of target
                if tIdx == 0 {
                    totalScore += 0.2
                }

                // Bonus: match at start of word (after space, dash, dot, etc.)
                if tIdx > 0 {
                    let prevChar = targetChars[tIdx - 1]
                    if prevChar == " " || prevChar == "-" || prevChar == "." || prevChar == "_" {
                        totalScore += 0.15
                    }
                }

                // Bonus: consecutive match
                if matchedIndices.count >= 2,
                   matchedIndices[matchedIndices.count - 1] == matchedIndices[matchedIndices.count - 2] + 1
                {
                    totalScore += 0.1
                }

                // Base score for matching
                totalScore += 0.05

                qIdx += 1
            }
        }

        // All query characters must match
        guard qIdx == queryChars.count else { return nil }

        // Penalty for gaps between matches
        if let first = matchedIndices.first, let last = matchedIndices.last, matchedIndices.count >= 2 {
            let totalGap = last - first - (matchedIndices.count - 1)
            totalScore -= Double(totalGap) * 0.02
        }

        // Normalize score to 0..1 range
        let maxPossible = Double(queryChars.count) * 0.35 + 0.2
        let normalizedScore = min(1.0, max(0.0, totalScore / maxPossible))

        // Build ranges for highlighting
        let matchedRanges = buildRanges(from: matchedIndices, in: original)

        return MatchResult(score: normalizedScore, matchedRanges: matchedRanges)
    }

    /// Precomputed lowercase forms of one action's searchable fields. Built once
    /// per action when the corpus is (re)fetched so per-keystroke scoring does no
    /// string lowercasing or `Array(String)` conversion.
    struct ScoreTarget: Sendable {
        let title: String
        let titleChars: [Character]
        let subtitle: String
        let subtitleChars: [Character]
        let keywordsLower: [String]
        let relevanceScore: Double

        init(title: String, subtitle: String, keywords: [String], relevanceScore: Double) {
            self.title = title
            self.titleChars = Array(title.lowercased())
            self.subtitle = subtitle
            self.subtitleChars = Array(subtitle.lowercased())
            self.keywordsLower = keywords.map { $0.lowercased() }
            self.relevanceScore = relevanceScore
        }
    }

    /// Score an action against a query, combining fuzzy match with module score and usage.
    /// Returns nil if the action doesn't match at all.
    static func score(
        query: String,
        title: String,
        subtitle: String,
        keywords: [String],
        relevanceScore: Double,
        usageBoost: Double
    ) -> (score: Double, titleRanges: [Range<String.Index>])? {
        let queryLower = query.lowercased()
        return score(
            queryLower: queryLower,
            queryChars: Array(queryLower),
            target: ScoreTarget(
                title: title,
                subtitle: subtitle,
                keywords: keywords,
                relevanceScore: relevanceScore
            ),
            usageBoost: usageBoost
        )
    }

    /// Precomputed-input variant of `score` — the per-keystroke hot path. All
    /// lowercased forms come in ready-made so no string transforms happen here.
    static func score(
        queryLower: String,
        queryChars: [Character],
        target: ScoreTarget,
        usageBoost: Double
    ) -> (score: Double, titleRanges: [Range<String.Index>])? {
        guard !queryChars.isEmpty else {
            // No query: score based on relevance and usage only
            let score = target.relevanceScore * 0.4 + usageBoost * 0.6
            return (score: score, titleRanges: [])
        }

        let titleMatch = match(
            queryChars: queryChars, against: target.titleChars, original: target.title
        )
        let subtitleMatch = match(
            queryChars: queryChars, against: target.subtitleChars, original: target.subtitle
        )
        let keywordMatch = target.keywordsLower.contains { $0.hasPrefix(queryLower) }

        // Must match at least title, subtitle, or keyword
        guard titleMatch != nil || subtitleMatch != nil || keywordMatch else {
            return nil
        }

        let titleScore = titleMatch?.score ?? 0
        let subtitleScore = subtitleMatch?.score ?? 0
        let keywordBonus: Double = keywordMatch ? 0.1 : 0

        let combined = titleScore * 0.4
            + subtitleScore * 0.1
            + keywordBonus
            + target.relevanceScore * 0.15
            + usageBoost * 0.25

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

        for i in 1 ..< indices.count {
            if indices[i] == rangeEndInt + 1 {
                rangeEndInt = indices[i]
            } else {
                let start = advance(to: rangeStartInt)
                let end = advance(to: rangeEndInt + 1)
                ranges.append(start ..< end)
                rangeStartInt = indices[i]
                rangeEndInt = indices[i]
            }
        }

        let start = advance(to: rangeStartInt)
        let end = advance(to: rangeEndInt + 1)
        ranges.append(start ..< end)

        return ranges
    }
}
