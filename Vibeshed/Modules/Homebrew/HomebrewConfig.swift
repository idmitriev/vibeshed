import Foundation

struct HomebrewConfig: Codable, Sendable, Equatable {
    var brewPath: String = "/opt/homebrew/bin/brew"
    var enabledActions: Set<String>?
}

extension HomebrewConfig {
    /// Every key is optional: a missing one keeps its default above instead of failing
    /// the whole section (see `ApplicationConfig`).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        brewPath = try container.decodeIfPresent(String.self, forKey: .brewPath) ?? defaults.brewPath
        enabledActions = try container.decodeIfPresent(Set<String>.self, forKey: .enabledActions)
    }
}
