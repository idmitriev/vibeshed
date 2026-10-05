import Foundation

struct JetBrainsConfig: Codable, Sendable, Equatable {
    var maxResults: Int = 20
    var enabledActions: Set<String>?
    var enabledIDEs: Set<String>?
    var openInNewWindow: Bool = false
}

extension JetBrainsConfig {
    /// Every key is optional: a missing one keeps its default above instead of failing
    /// the whole section (see `ApplicationConfig`).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        maxResults = try container.decodeIfPresent(Int.self, forKey: .maxResults) ?? defaults.maxResults
        enabledActions = try container.decodeIfPresent(Set<String>.self, forKey: .enabledActions)
        enabledIDEs = try container.decodeIfPresent(Set<String>.self, forKey: .enabledIDEs)
        openInNewWindow = try container.decodeIfPresent(Bool.self, forKey: .openInNewWindow)
            ?? defaults.openInNewWindow
    }
}
