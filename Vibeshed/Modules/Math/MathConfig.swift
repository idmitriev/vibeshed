import Foundation

struct MathConfig: Codable, Sendable, Equatable {
    /// Maximum decimal places for results (trailing zeros stripped)
    var decimalPlaces: Int = 6

    /// Whether to fetch live currency exchange rates
    var enableCurrency: Bool = true

    /// Currency rate cache TTL in seconds
    var currencyRateTTL: Int = 3600

    /// Copy result to clipboard on action execution
    var copyOnSelect: Bool = true

    /// Show hex/bin/oct conversions for integer results
    var showBaseConversions: Bool = true

    /// Restrict to specific action types (nil = all)
    var enabledActions: Set<String>?
}
