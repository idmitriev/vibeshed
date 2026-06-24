import Foundation

/// Pure, actor-independent scoring/ranking of actions into display items.
///
/// This is the per-keystroke hot path (fuzzy scoring + sort + URL dedup over the full
/// combined action set). It takes only `Sendable` inputs and returns `Sendable` output
/// so `PickerCoordinator` can run it off the main actor via `Task.detached`, keeping
/// scoring off the main thread during typing.
enum ActionScorer {
    /// Maximum rendered results — nobody scrolls past 200 in a launcher.
    private static let maxResults = 200

    /// Scores `allActions` against `query`, ranks them, dedups browser tabs vs
    /// bookmark/history entries by URL, and caps the result.
    ///
    /// - Parameters:
    ///   - allActions: module actions plus any synthetic alias actions.
    ///   - enrichments: extra keywords contributed by aliases, keyed by action ID.
    static func scoreAndRank(
        allActions: [any Action],
        enrichments: [ActionID: [String]],
        query: String,
        scoring: ScoringContext
    ) -> ([ActionItem], [ActionID: any Action]) {
        var scored: [(item: ActionItem, action: any Action, score: Double)] = []
        var cache: [ActionID: any Action] = [:]

        for action in allActions {
            let combinedKeywords = action.keywords + (enrichments[action.id] ?? [])

            let usageBoost = scoring.usageBoost(for: action.id)
            guard let result = FuzzyMatcher.score(
                query: query,
                title: action.title,
                subtitle: action.subtitle,
                keywords: combinedKeywords,
                relevanceScore: action.relevanceScore,
                usageBoost: usageBoost
            ) else { continue }

            let moduleID = action.id.moduleID
            let contextBoost: Double = if let ctx = scoring.systemContext {
                ContextualScorer.boost(
                    actionID: action.id, moduleID: moduleID, context: ctx
                )
            } else {
                0
            }
            let finalScore = result.score + contextBoost

            let item = ActionItem(
                id: action.id,
                title: action.title,
                subtitle: action.subtitle,
                iconSystemName: action.iconName,
                score: finalScore,
                moduleID: moduleID,
                hasParameters: !action.parameters.filter(\.isRequired).isEmpty,
                keywords: combinedKeywords,
                titleHighlightRanges: result.titleRanges.isEmpty ? nil : result.titleRanges
            )
            scored.append((item: item, action: action, score: finalScore))
            cache[action.id] = action
        }

        scored.sort { $0.score > $1.score }

        // Collapse actions sharing a deduplication key (e.g. a browser tab and a
        // bookmark/history entry for the same URL). Higher-scored entries are kept
        // because they sort first, so the survivor is the better-ranked one.
        var seenKeys: Set<String> = []
        scored.removeAll { entry in
            guard let key = entry.action.deduplicationKey, !key.isEmpty else { return false }
            return !seenKeys.insert(key).inserted
        }

        if scored.count > maxResults {
            for entry in scored[maxResults...] {
                cache.removeValue(forKey: entry.action.id)
            }
            scored = Array(scored.prefix(maxResults))
        }

        return (scored.map(\.item), cache)
    }

    static func normalizeURL(_ url: String) -> String {
        var s = url.lowercased()
        if let i = s.firstIndex(of: "#") { s = String(s[..<i]) }
        while s.hasSuffix("/") {
            s.removeLast()
        }
        return s
    }
}
