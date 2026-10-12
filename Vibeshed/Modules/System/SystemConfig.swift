import Foundation

struct SystemConfig: Codable, Sendable, Equatable {
    var screenshotPath: String = "~/Desktop"
    var enabledActions: Set<String>?
}

extension SystemConfig {
    /// Every key is optional: a missing one keeps its default above instead of failing
    /// the whole section (see `ApplicationConfig`).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        screenshotPath = try container.decodeIfPresent(String.self, forKey: .screenshotPath) ?? defaults.screenshotPath
        enabledActions = try container.decodeIfPresent(Set<String>.self, forKey: .enabledActions)
    }
}
