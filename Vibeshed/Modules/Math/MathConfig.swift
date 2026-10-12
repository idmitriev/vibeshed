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

extension MathConfig {
    /// Every key is optional: a missing one keeps its default above instead of failing
    /// the whole section (see `ApplicationConfig`).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        decimalPlaces = try container.decodeIfPresent(Int.self, forKey: .decimalPlaces) ?? defaults.decimalPlaces
        enableCurrency = try container.decodeIfPresent(Bool.self, forKey: .enableCurrency) ?? defaults.enableCurrency
        currencyRateTTL = try container.decodeIfPresent(Int.self, forKey: .currencyRateTTL)
            ?? defaults.currencyRateTTL
        copyOnSelect = try container.decodeIfPresent(Bool.self, forKey: .copyOnSelect) ?? defaults.copyOnSelect
        showBaseConversions = try container.decodeIfPresent(Bool.self, forKey: .showBaseConversions)
            ?? defaults.showBaseConversions
        enabledActions = try container.decodeIfPresent(Set<String>.self, forKey: .enabledActions)
    }
}
