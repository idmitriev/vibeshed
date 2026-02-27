import Foundation
import SwiftUI

enum MeetingPrepActionType: String, Sendable {
    case prepForMeeting
    case hideDistractions
    case restoreWindows
    case joinVideo
    case utility
}

struct MeetingPrepAction: Action {
    let id: ActionID
    let title: String
    let subtitle: String
    let iconName: String?
    let relevanceScore: Double
    let keywords: [String]
    let parameters: [ActionParameter]

    let actionType: MeetingPrepActionType
    let meetingTitle: String?
    let startDate: Date?
    let endDate: Date?
    let attendeeNames: [String]?
    let videoLinkType: VideoLinkType?
    let videoURL: URL?
    let calendarName: String?
    let calendarColorHex: String?

    private let runner: @Sendable (
        [String: Any]
    ) async throws -> ActionResult

    init(
        id: ActionID,
        title: String,
        subtitle: String,
        iconName: String? = nil,
        relevanceScore: Double = 0.8,
        keywords: [String] = [],
        parameters: [ActionParameter] = [],
        actionType: MeetingPrepActionType = .utility,
        meetingTitle: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        attendeeNames: [String]? = nil,
        videoLinkType: VideoLinkType? = nil,
        videoURL: URL? = nil,
        calendarName: String? = nil,
        calendarColorHex: String? = nil,
        runner: @escaping @Sendable (
            [String: Any]
        ) async throws -> ActionResult
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.relevanceScore = relevanceScore
        self.keywords = keywords
        self.parameters = parameters
        self.actionType = actionType
        self.meetingTitle = meetingTitle
        self.startDate = startDate
        self.endDate = endDate
        self.attendeeNames = attendeeNames
        self.videoLinkType = videoLinkType
        self.videoURL = videoURL
        self.calendarName = calendarName
        self.calendarColorHex = calendarColorHex
        self.runner = runner
    }

    func run(with values: [String: Any]) async throws -> ActionResult {
        try await runner(values)
    }

    @MainActor
    func makeListItemView() -> AnyView? {
        AnyView(MeetingPrepListItemView(action: self))
    }

    @MainActor
    func makePreviewView() -> AnyView? {
        AnyView(MeetingPrepPreviewView(action: self))
    }
}
