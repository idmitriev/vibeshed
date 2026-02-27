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
