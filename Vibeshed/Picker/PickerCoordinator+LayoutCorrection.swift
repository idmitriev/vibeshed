import Foundation

extension PickerCoordinator {
    struct LayoutCorrectedResults {
        let hint: LayoutCorrectionHint
        let items: [ActionItem]
        let cache: [ActionID: any Action]
        let combined: [ScorableAction]
        let scoring: ScoringContext
    }

    /// Scores each Latin reading of `query` and keeps the one whose best real
    /// (non-fallback) match scores highest; nil when none matches anything real.
    func bestLayoutCorrection(
        of query: String,
        corpus: [ScorableAction],
        context: SystemContext?
    ) async -> LayoutCorrectedResults? {
        guard let hints = layoutTransliterator?.corrections(for: query), !hints.isEmpty else { return nil }

        var best: (results: LayoutCorrectedResults, score: Double)?
        for hint in hints {
            let scoring = makeScoring(query: hint.correctedQuery, context: context)
            let (items, cache, combined) = await scoreQuery(hint.correctedQuery, corpus: corpus, scoring: scoring)
            guard let score = Self.topRankedScore(items, cache), score > (best?.score ?? -.infinity) else { continue }
            best = (LayoutCorrectedResults(
                hint: hint, items: items, cache: cache, combined: combined, scoring: scoring
            ), score)
        }
        return best?.results
    }

    /// Score of the best non-fallback result; nil when only catch-alls such as web
    /// search matched, which they do for any query.
    static func topRankedScore(_ items: [ActionItem], _ cache: [ActionID: any Action]) -> Double? {
        items.first { cache[$0.id]?.isFallback == false }?.score
    }
}
