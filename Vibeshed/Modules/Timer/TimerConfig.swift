import Foundation

struct TimerConfig: Codable, Sendable, Equatable {
    var defaultSound: String = "Glass"
    var presetDurations: [Int] = [1, 5, 10, 15, 30, 60]
    var maxActiveTimers: Int = 20
    var enabledActions: Set<String>?
}

extension TimerConfig {
    /// Every key is optional: a missing one keeps its default above instead of failing
    /// the whole section (see `ApplicationConfig`).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        defaultSound = try container.decodeIfPresent(String.self, forKey: .defaultSound) ?? defaults.defaultSound
        presetDurations = try container.decodeIfPresent([Int].self, forKey: .presetDurations)
            ?? defaults.presetDurations
        maxActiveTimers = try container.decodeIfPresent(Int.self, forKey: .maxActiveTimers)
            ?? defaults.maxActiveTimers
        enabledActions = try container.decodeIfPresent(Set<String>.self, forKey: .enabledActions)
    }
}
