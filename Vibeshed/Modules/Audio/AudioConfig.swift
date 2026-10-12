import Foundation

struct AudioConfig: Codable, Sendable, Equatable {
    var volumeSteps: [Int] = [20, 50, 80]
    var volumeStep: Int = 10
    var enabledActions: Set<String>?
}

extension AudioConfig {
    /// Every key is optional: a missing one keeps its default above instead of failing
    /// the whole section (see `ApplicationConfig`).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        volumeSteps = try container.decodeIfPresent([Int].self, forKey: .volumeSteps) ?? defaults.volumeSteps
        volumeStep = try container.decodeIfPresent(Int.self, forKey: .volumeStep) ?? defaults.volumeStep
        enabledActions = try container.decodeIfPresent(Set<String>.self, forKey: .enabledActions)
    }
}
