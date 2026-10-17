import Foundation

/// Which action the user ran from the picker after typing which query — so a query
/// they keep typing brings up what they keep choosing for it, without that choice
/// leaking into unrelated queries the way per-action usage does.
///
/// Each (action, query) pair holds a pick count that halves every `halfLife`, so old
/// habits fade. `shares(for:now:)` turns them into each action's share of the picks
/// made for what's typed now.
struct QueryHistory: Codable, Sendable, Equatable {
    struct Entry: Codable, Sendable, Equatable {
        var weight: Double
        var lastUsed: Date
    }

    static let halfLife: TimeInterval = 30 * 24 * 3600
    /// Queries kept per action; the faintest go first.
    static let queriesPerAction = 8
    /// Longer text is cut to this length: habits are short, and nothing more of what
    /// was typed needs to be stored.
    static let maxQueryLength = 40
    /// Entries that have faded below this weight are dropped when saving.
    static let minimumWeight = 0.05

    /// Action ID → normalized query → entry.
    private(set) var picks: [String: [String: Entry]] = [:]

    /// Lowercased and trimmed; nil for an empty query, which ranks by usage alone.
    static func normalize(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maxQueryLength))
    }

    mutating func record(query: String, actionID: String, at now: Date) {
        guard let query = Self.normalize(query) else { return }
        var entries = picks[actionID] ?? [:]
        let previous = entries[query].map { Self.decayed($0, at: now) } ?? 0
        entries[query] = Entry(weight: previous + 1, lastUsed: now)
        if entries.count > Self.queriesPerAction,
           let faintest = entries.min(by: { Self.decayed($0.value, at: now) < Self.decayed($1.value, at: now) })
        {
            entries[faintest.key] = nil
        }
        picks[actionID] = entries
    }

    /// Each action's share, in 0..<1, of the picks made after typing a query related
    /// to `query`: one it starts (typed "th", picked after "theme") counts fully, one
    /// it extends (typed "theme", picked after "th") by the fraction already typed then.
    /// The +1 in the denominator keeps a single pick from claiming certainty, and lets
    /// a few picks for one action outweigh a stray pick for another.
    func shares(for query: String, now: Date) -> [String: Double] {
        guard let query = Self.normalize(query) else { return [:] }
        var perAction: [String: Double] = [:]
        var total = 0.0
        for (actionID, entries) in picks {
            var sum = 0.0
            for (picked, entry) in entries {
                let relation: Double = if picked.hasPrefix(query) {
                    1
                } else if query.hasPrefix(picked) {
                    Double(picked.count) / Double(query.count)
                } else {
                    0
                }
                guard relation > 0 else { continue }
                sum += relation * Self.decayed(entry, at: now)
            }
            guard sum > 0 else { continue }
            perAction[actionID] = sum
            total += sum
        }
        return perAction.mapValues { $0 / (total + 1) }
    }

    /// Without the entries that have faded out.
    func pruned(at now: Date) -> QueryHistory {
        var copy = self
        copy.picks = picks.compactMapValues { entries in
            let kept = entries.filter { Self.decayed($0.value, at: now) >= Self.minimumWeight }
            return kept.isEmpty ? nil : kept
        }
        return copy
    }

    private static func decayed(_ entry: Entry, at now: Date) -> Double {
        let age = max(0, now.timeIntervalSince(entry.lastUsed))
        return entry.weight * pow(0.5, age / halfLife)
    }
}
