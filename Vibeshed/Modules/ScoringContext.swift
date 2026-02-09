import Foundation

struct ScoringContext: Sendable {
    let usageCounts: [String: Int]
    let lastUsedDates: [String: Date]
    let query: String

    func recencyScore(for actionID: ActionID) -> Double {
        guard let lastUsed = lastUsedDates[actionID.rawValue] else { return 0 }
        let elapsed = Date().timeIntervalSince(lastUsed)
        return exp(-elapsed / 3600.0)
    }

    func frequencyScore(for actionID: ActionID) -> Double {
        guard let count = usageCounts[actionID.rawValue], count > 0 else { return 0 }
        return min(1.0, log(Double(count) + 1) / log(51.0))
    }

    func usageBoost(for actionID: ActionID, recencyWeight: Double = 0.6) -> Double {
        let r = recencyScore(for: actionID)
        let f = frequencyScore(for: actionID)
        return r * recencyWeight + f * (1.0 - recencyWeight)
    }
}
