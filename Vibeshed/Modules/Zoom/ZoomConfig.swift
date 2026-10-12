import Foundation

struct ZoomMeetingEntry: Codable, Sendable, Equatable {
    let name: String
    var meetingId: String?
    var password: String?
    var link: String?
    var keywords: [String]?
    var icon: String?
}

struct ZoomConfig: Codable, Sendable, Equatable {
    var meetings: [ZoomMeetingEntry] = []
    var personalMeetingId: String?
    var showStartMeeting: Bool = true
    var showJoinAction: Bool = true
    var showLaunchAction: Bool = true
    var enabledActions: Set<String>?
}

extension ZoomConfig {
    /// Every key is optional: a missing one keeps its default above instead of failing
    /// the whole section (see `ApplicationConfig`).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        meetings = try container.decodeIfPresent([ZoomMeetingEntry].self, forKey: .meetings) ?? defaults.meetings
        personalMeetingId = try container.decodeIfPresent(String.self, forKey: .personalMeetingId)
        showStartMeeting = try container.decodeIfPresent(Bool.self, forKey: .showStartMeeting)
            ?? defaults.showStartMeeting
        showJoinAction = try container.decodeIfPresent(Bool.self, forKey: .showJoinAction) ?? defaults.showJoinAction
        showLaunchAction = try container.decodeIfPresent(Bool.self, forKey: .showLaunchAction)
            ?? defaults.showLaunchAction
        enabledActions = try container.decodeIfPresent(Set<String>.self, forKey: .enabledActions)
    }
}
