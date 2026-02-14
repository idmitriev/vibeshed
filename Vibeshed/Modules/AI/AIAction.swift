import Foundation
import SwiftUI

enum AIItemType: String, Sendable {
    case session
    case launcher
    case search
}

struct AIAction: Action {
    let id: ActionID
    let title: String
    let subtitle: String
    let iconName: String?
    let relevanceScore: Double
    let keywords: [String]
    let parameters: [ActionParameter]

    let provider: AIProvider?
    let aiItemType: AIItemType?
    let projectPath: String?
    let modelName: String?
    let sessionTimestamp: Date?

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
        provider: AIProvider? = nil,
        aiItemType: AIItemType? = nil,
        projectPath: String? = nil,
        modelName: String? = nil,
        sessionTimestamp: Date? = nil,
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
        self.provider = provider
        self.aiItemType = aiItemType
        self.projectPath = projectPath
        self.modelName = modelName
        self.sessionTimestamp = sessionTimestamp
        self.runner = runner
    }

    func run(with values: [String: Any]) async throws -> ActionResult {
        try await runner(values)
    }

    @MainActor
    func makeListItemView() -> AnyView? {
        AnyView(AIActionListItemView(action: self))
    }

    @MainActor
    func makePreviewView() -> AnyView? {
        AnyView(AIActionPreviewView(action: self))
    }
}
