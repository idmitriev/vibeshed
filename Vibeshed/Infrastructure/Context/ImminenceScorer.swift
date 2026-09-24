import Foundation

/// Ranks time-bound actions (calendar events, meetings to join) by how close they
/// are to starting.
///
/// Unlike `ContextualScorer`, whose boosts are deliberately small nudges clamped to
/// ±0.15, this one is intended to dominate: a meeting that starts in two minutes
/// should sit at the top of the list even when the query matches some other action
/// far more precisely. The fuzzy matcher still gates *whether* an action appears at
/// all, so a boosted event never shows up for a query it doesn't match.
enum ImminenceScorer {
    /// Additive boost for an event that is starting right now. Roughly the size of a
    /// full composite score, so an imminent event outranks a perfect match elsewhere.
    static let maxBoost = 1.0

    /// Events starting within this many minutes get the undiminished boost.
    static let peakWindowMinutes = 5.0

    /// Beyond this horizon the boost is zero; between the peak window and here it
    /// decays linearly.
    static let horizonMinutes = 120.0

    /// How long after an event starts it still counts as "just started".
    static let underwayPeakMinutes = 15.0

    /// Boost held by an event that is under way but past `underwayPeakMinutes` —
    /// still worth surfacing, no longer urgent. Keeps a long block (a 3-hour focus
    /// slot) from pinning itself to the top of the list all afternoon.
    static let underwayPlateau = 0.5

    /// Grace period applied to a started event with no known end time.
    private static let missingEndGraceMinutes = 30.0

    /// Additive score boost in `0...maxBoost` for an action's scheduled window.
    static func boost(
        scheduledStart: Date?,
        scheduledEnd: Date?,
        now: Date
    ) -> Double {
        guard let start = scheduledStart else { return 0 }
        let minutesUntilStart = start.timeIntervalSince(now) / 60

        guard minutesUntilStart > 0 else {
            return underwayBoost(
                minutesSinceStart: -minutesUntilStart,
                scheduledEnd: scheduledEnd,
                now: now
            )
        }

        if minutesUntilStart <= peakWindowMinutes { return maxBoost }
        guard minutesUntilStart < horizonMinutes else { return 0 }

        let remaining = horizonMinutes - minutesUntilStart
        let span = horizonMinutes - peakWindowMinutes
        return maxBoost * (remaining / span)
    }

    /// Convenience over the action itself.
    static func boost(for action: some Action, now: Date) -> Double {
        boost(
            scheduledStart: action.scheduledStart,
            scheduledEnd: action.scheduledEnd,
            now: now
        )
    }

    private static func underwayBoost(
        minutesSinceStart: Double,
        scheduledEnd: Date?,
        now: Date
    ) -> Double {
        if let end = scheduledEnd {
            guard now < end else { return 0 }
        } else {
            // No end time to bound it, so stop boosting once the start is stale.
            guard minutesSinceStart <= missingEndGraceMinutes else { return 0 }
        }
        return minutesSinceStart <= underwayPeakMinutes
            ? maxBoost
            : maxBoost * underwayPlateau
    }
}
