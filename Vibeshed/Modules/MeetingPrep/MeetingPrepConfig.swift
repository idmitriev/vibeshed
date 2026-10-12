import Foundation

struct MeetingPrepConfig: Codable, Sendable, Equatable {
    /// Minutes before meeting start to show prep actions
    var prepWindowMinutes: Int = 15

    /// App bundle IDs to minimize when preparing for a meeting
    var hideApps: [String]?

    /// App bundle IDs to keep visible during meeting prep
    var keepApps: [String]?

    /// Whether to auto-join video call when preparing
    var autoJoinVideo: Bool = false

    /// Enabled actions filter (nil = all)
    var enabledActions: Set<String>?
}

extension MeetingPrepConfig {
    /// Every key is optional: a missing one keeps its default above instead of failing
    /// the whole section (see `ApplicationConfig`).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        prepWindowMinutes = try container.decodeIfPresent(Int.self, forKey: .prepWindowMinutes)
            ?? defaults.prepWindowMinutes
        hideApps = try container.decodeIfPresent([String].self, forKey: .hideApps)
        keepApps = try container.decodeIfPresent([String].self, forKey: .keepApps)
        autoJoinVideo = try container.decodeIfPresent(Bool.self, forKey: .autoJoinVideo) ?? defaults.autoJoinVideo
        enabledActions = try container.decodeIfPresent(Set<String>.self, forKey: .enabledActions)
    }
}
