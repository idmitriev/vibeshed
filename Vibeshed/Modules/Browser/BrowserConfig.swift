import Foundation

struct BrowserConfig: Codable, Sendable, Equatable {
    /// Which browsers to query. Empty means all running supported browsers.
    var browsers: [String] = []

    /// How many seconds to cache tab listings before re-querying.
    var cacheTTLSeconds: Double = 3.0

    /// Maximum number of tabs to show in results (0 = unlimited).
    var maxResults: Int = 0

    /// Whether to show "Close Tab" actions alongside focus actions.
    var showCloseActions: Bool = true
}

extension BrowserConfig {
    /// Every key is optional: a missing one keeps its default above instead of failing
    /// the whole section (see `ApplicationConfig`).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        browsers = try container.decodeIfPresent([String].self, forKey: .browsers) ?? defaults.browsers
        cacheTTLSeconds = try container.decodeIfPresent(Double.self, forKey: .cacheTTLSeconds)
            ?? defaults.cacheTTLSeconds
        maxResults = try container.decodeIfPresent(Int.self, forKey: .maxResults) ?? defaults.maxResults
        showCloseActions = try container.decodeIfPresent(Bool.self, forKey: .showCloseActions)
            ?? defaults.showCloseActions
    }
}
