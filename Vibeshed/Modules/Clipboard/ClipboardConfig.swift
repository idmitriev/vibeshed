import Foundation

struct ClipboardConfig: Codable, Sendable, Equatable {
    var maxItems: Int = 100
    var pollingInterval: Double = 0.5
    var excludePatterns: [String]?
    var showClearAction: Bool = true
    var pasteOnSelect: Bool = true
    var enabledActions: Set<String>?
}

extension ClipboardConfig {
    /// Every key is optional: a missing one keeps its default above instead of failing
    /// the whole section (see `ApplicationConfig`).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        maxItems = try container.decodeIfPresent(Int.self, forKey: .maxItems) ?? defaults.maxItems
        pollingInterval = try container.decodeIfPresent(Double.self, forKey: .pollingInterval)
            ?? defaults.pollingInterval
        excludePatterns = try container.decodeIfPresent([String].self, forKey: .excludePatterns)
        showClearAction = try container.decodeIfPresent(Bool.self, forKey: .showClearAction)
            ?? defaults.showClearAction
        pasteOnSelect = try container.decodeIfPresent(Bool.self, forKey: .pasteOnSelect) ?? defaults.pasteOnSelect
        enabledActions = try container.decodeIfPresent(Set<String>.self, forKey: .enabledActions)
    }
}
