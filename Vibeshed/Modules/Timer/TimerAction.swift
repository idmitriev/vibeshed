import Foundation
import SwiftUI

enum TimerItemType: String, Sendable {
    case timer
    case reminder
    case utility
}

struct TimerAction: Action {
    let id: ActionID
    let title: String
    let subtitle: String
    let iconName: String?
    let relevanceScore: Double
    let keywords: [String]
    let parameters: [ActionParameter]

    let timerItemType: TimerItemType
    let fireDate: Date?
    let createdDate: Date?
    let originalDuration: TimeInterval?
    let label: String?
    let isActive: Bool

    private let runner: @Sendable ([String: Any]) async throws -> ActionResult

    init(
        id: ActionID,
        title: String,
        subtitle: String,
        iconName: String? = nil,
        relevanceScore: Double = 0.8,
        keywords: [String] = [],
        parameters: [ActionParameter] = [],
        timerItemType: TimerItemType = .utility,
        fireDate: Date? = nil,
        createdDate: Date? = nil,
        originalDuration: TimeInterval? = nil,
        label: String? = nil,
        isActive: Bool = false,
        runner: @escaping @Sendable ([String: Any]) async throws -> ActionResult
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.relevanceScore = relevanceScore
        self.keywords = keywords
        self.parameters = parameters
        self.timerItemType = timerItemType
        self.fireDate = fireDate
        self.createdDate = createdDate
        self.originalDuration = originalDuration
        self.label = label
        self.isActive = isActive
        self.runner = runner
    }

    func run(with values: [String: Any]) async throws -> ActionResult {
        try await runner(values)
    }

    @MainActor
    func makeListItemView() -> AnyView? {
        AnyView(TimerActionListItemView(action: self))
    }

    @MainActor
    func makePreviewView() -> AnyView? {
        AnyView(TimerActionPreviewView(action: self))
    }
}
