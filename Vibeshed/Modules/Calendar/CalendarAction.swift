import Foundation
import SwiftUI

enum CalendarItemType: String, Sendable {
    case event
    case utility
}

enum VideoLinkType: String, Sendable {
    case zoom
    case googleMeet
    case teams
}

struct CalendarAction: Action {
    let id: ActionID
    let title: String
    let subtitle: String
    let iconName: String?
    let relevanceScore: Double
    let keywords: [String]
    let parameters: [ActionParameter]

    let calendarItemType: CalendarItemType
    let calendarName: String?
    let calendarColorHex: String?
    let startDate: Date?
    let endDate: Date?
    let isAllDay: Bool
    let location: String?
    let attendeeNames: [String]?
    let videoLinkType: VideoLinkType?
    let videoURL: URL?

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
        calendarItemType: CalendarItemType = .event,
        calendarName: String? = nil,
        calendarColorHex: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        isAllDay: Bool = false,
        location: String? = nil,
        attendeeNames: [String]? = nil,
        videoLinkType: VideoLinkType? = nil,
        videoURL: URL? = nil,
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
        self.calendarItemType = calendarItemType
        self.calendarName = calendarName
        self.calendarColorHex = calendarColorHex
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
        self.attendeeNames = attendeeNames
        self.videoLinkType = videoLinkType
        self.videoURL = videoURL
        self.runner = runner
    }

    func run(with values: [String: Any]) async throws -> ActionResult {
        try await runner(values)
    }

    @MainActor
    func makeListItemView() -> AnyView? {
        AnyView(CalendarActionListItemView(action: self))
    }

    @MainActor
    func makePreviewView() -> AnyView? {
        AnyView(CalendarActionPreviewView(action: self))
    }
}
