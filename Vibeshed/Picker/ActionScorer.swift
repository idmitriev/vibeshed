import Foundation

/// An action bundled with the precomputed lowercase forms the fuzzy matcher needs.
/// Built once when the catalog corpus is (re)fetched, so per-keystroke scoring does
/// no string lowercasing or `Array(String)` conversion at all.
struct ScorableAction: Sendable {
    let action: any Action
    /// Keywords including any alias enrichments, in original casing (shown in UI).
    let keywords: [String]
    let target: FuzzyMatcher.ScoreTarget
    /// Scheduled window, hoisted out of the action so the per-keystroke imminence
    /// boost needs no witness-table lookups.
    let scheduledStart: Date?
    let scheduledEnd: Date?

    init(action: any Action, extraKeywords: [String] = []) {
        self.action = action
        let combined = action.keywords + extraKeywords
        self.keywords = combined
        self.scheduledStart = action.scheduledStart
        self.scheduledEnd = action.scheduledEnd
        self.target = FuzzyMatcher.ScoreTarget(
            title: action.title,
            subtitle: action.subtitle,
            keywords: combined,
            relevanceScore: action.relevanceScore
        )
    }
}

/// Pure, actor-independent scoring/ranking of actions into display items.
///
/// This is the per-keystroke hot path (fuzzy scoring + sort + URL dedup over the full
/// combined action set). It takes only `Sendable` inputs and returns `Sendable` output
/// so `PickerCoordinator` can run it off the main actor via `Task.detached`, keeping
/// scoring off the main thread during typing.
enum ActionScorer {
    /// Maximum rendered results — nobody scrolls past 200 in a launcher.
    private static let maxResults = 200

    /// Scores the precomputed corpus against `query`, ranks it, dedups browser tabs vs
    /// bookmark/history entries by URL, and caps the result.
    static func scoreAndRank(
        corpus: [ScorableAction],
        query: String,
        scoring: ScoringContext
    ) -> ([ActionItem], [ActionID: any Action]) {
        let queryLower = query.lowercased()
        let queryChars = Array(queryLower)

        var scored: [(item: ActionItem, action: any Action, score: Double)] = []
        var cache: [ActionID: any Action] = [:]

        for scorable in corpus {
            let action = scorable.action
            let usageBoost = scoring.usageBoost(for: action.id)
            guard let result = FuzzyMatcher.score(
                queryLower: queryLower,
                queryChars: queryChars,
                target: scorable.target,
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
            // Deliberately unclamped and applied on top: an event about to start
            // outranks even an exact match elsewhere in the list.
            let imminenceBoost = ImminenceScorer.boost(
                scheduledStart: scorable.scheduledStart,
                scheduledEnd: scorable.scheduledEnd,
                now: scoring.now
            )
            let finalScore = result.score + contextBoost + imminenceBoost

            let item = ActionItem(
                id: action.id,
                title: action.title,
                subtitle: action.subtitle,
                iconSystemName: action.iconName,
                appIconPath: action.appIconPath,
                score: finalScore,
                moduleID: moduleID,
                hasParameters: !action.parameters.filter(\.isRequired).isEmpty,
                keywords: scorable.keywords,
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

    /// Convenience over the corpus variant for callers holding raw actions —
    /// builds the precomputed forms inline. Equivalent output.
    static func scoreAndRank(
        allActions: [any Action],
        enrichments: [ActionID: [String]],
        query: String,
        scoring: ScoringContext
    ) -> ([ActionItem], [ActionID: any Action]) {
        let corpus = allActions.map {
            ScorableAction(action: $0, extraKeywords: enrichments[$0.id] ?? [])
        }
        return scoreAndRank(corpus: corpus, query: query, scoring: scoring)
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
