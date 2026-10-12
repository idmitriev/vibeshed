import Foundation

struct ZedConfig: Codable, Sendable, Equatable {
    var maxResults: Int = 20
    var showRemote: Bool = false
    var enabledActions: Set<String>?
    var zedPath: String?
}

extension ZedConfig {
    /// Every key is optional: a missing one keeps its default above instead of failing
    /// the whole section (see `ApplicationConfig`).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        maxResults = try container.decodeIfPresent(Int.self, forKey: .maxResults) ?? defaults.maxResults
        showRemote = try container.decodeIfPresent(Bool.self, forKey: .showRemote) ?? defaults.showRemote
        enabledActions = try container.decodeIfPresent(Set<String>.self, forKey: .enabledActions)
        zedPath = try container.decodeIfPresent(String.self, forKey: .zedPath)
    }
}
