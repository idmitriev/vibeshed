import Foundation

enum FuzzyMatcher {
    struct MatchResult {
        let score: Double
        let matchedRanges: [Range<String.Index>]
    }

    /// Fuzzy match a query against a target string.
    /// Returns nil if the query cannot be matched, otherwise returns a score (0..1) and highlight ranges.
    static func match(query: String, against target: String) -> MatchResult? {
        guard !query.isEmpty else {
            return MatchResult(score: 1.0, matchedRanges: [])
        }
        guard !target.isEmpty else { return nil }

        let queryLower = query.lowercased()
        let targetLower = target.lowercased()
        let queryChars = Array(queryLower)
        let targetChars = Array(targetLower)

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
        if matchedIndices.count >= 2 {
            let totalGap = matchedIndices.last! - matchedIndices.first! - (matchedIndices.count - 1)
            totalScore -= Double(totalGap) * 0.02
        }

        // Normalize score to 0..1 range
        let maxPossible = Double(queryChars.count) * 0.35 + 0.2
        let normalizedScore = min(1.0, max(0.0, totalScore / maxPossible))

        // Build ranges for highlighting
        let matchedRanges = buildRanges(from: matchedIndices, in: target)

        return MatchResult(score: normalizedScore, matchedRanges: matchedRanges)
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
        guard !query.isEmpty else {
            // No query: score based on relevance and usage only
            let score = relevanceScore * 0.4 + usageBoost * 0.6
            return (score: score, titleRanges: [])
        }

        let titleMatch = match(query: query, against: title)
        let subtitleMatch = match(query: query, against: subtitle)
        let keywordMatch = keywords.contains { $0.lowercased().hasPrefix(query.lowercased()) }

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
            + relevanceScore * 0.15
            + usageBoost * 0.25

        return (
            score: combined,
            titleRanges: titleMatch?.matchedRanges ?? []
        )
    }

    // MARK: - Private

    private static func buildRanges(from indices: [Int], in string: String) -> [Range<String.Index>] {
        guard !indices.isEmpty else { return [] }

        var ranges: [Range<String.Index>] = []
        let stringIndex = Array(string.indices) + [string.endIndex]
        guard stringIndex.count > indices.last! else { return [] }

        var rangeStart = indices[0]
        var rangeEnd = indices[0]

        for i in 1 ..< indices.count {
            if indices[i] == rangeEnd + 1 {
                rangeEnd = indices[i]
            } else {
                let start = stringIndex[rangeStart]
                let end = stringIndex[rangeEnd + 1]
                ranges.append(start ..< end)
                rangeStart = indices[i]
                rangeEnd = indices[i]
            }
        }

        let start = stringIndex[rangeStart]
        let end = stringIndex[rangeEnd + 1]
        ranges.append(start ..< end)

        return ranges
    }
}
