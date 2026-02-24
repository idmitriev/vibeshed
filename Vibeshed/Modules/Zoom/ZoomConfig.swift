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
