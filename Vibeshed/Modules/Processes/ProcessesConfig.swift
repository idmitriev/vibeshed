import Foundation

struct ProcessesConfig: Codable, Sendable, Equatable {
    var cacheTTLSeconds: Double = 2.0
    var maxResults: Int = 100
    var excludedNames: [String] = []
}

extension ProcessesConfig {
    /// Every key is optional: a missing one keeps its default above instead of failing
    /// the whole section (see `ApplicationConfig`).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        cacheTTLSeconds = try container.decodeIfPresent(Double.self, forKey: .cacheTTLSeconds)
            ?? defaults.cacheTTLSeconds
        maxResults = try container.decodeIfPresent(Int.self, forKey: .maxResults) ?? defaults.maxResults
        excludedNames = try container.decodeIfPresent([String].self, forKey: .excludedNames) ?? defaults.excludedNames
    }
}
