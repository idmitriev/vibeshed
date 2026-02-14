import SwiftUI

enum ITermItemType: String, Sendable {
    case session
    case newTab
    case newWindow
    case command
}

struct ITermAction: Action {
    let id: ActionID
    let title: String
    let subtitle: String
    let iconName: String?
    let relevanceScore: Double
    let keywords: [String]
    let parameters: [ActionParameter]

    let itermItemType: ITermItemType?
    let sessionPath: String?
    let jobName: String?
    let profileName: String?
    let isAtPrompt: Bool?

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
        itermItemType: ITermItemType? = nil,
        sessionPath: String? = nil,
        jobName: String? = nil,
        profileName: String? = nil,
        isAtPrompt: Bool? = nil,
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
        self.itermItemType = itermItemType
        self.sessionPath = sessionPath
        self.jobName = jobName
        self.profileName = profileName
        self.isAtPrompt = isAtPrompt
        self.runner = runner
    }

    func run(
        with values: [String: Any]
    ) async throws -> ActionResult {
        try await runner(values)
    }

    @MainActor
    func makeListItemView() -> AnyView? {
        AnyView(ITermActionListItemView(action: self))
    }

    @MainActor
    func makePreviewView() -> AnyView? {
        AnyView(ITermActionPreviewView(action: self))
    }
}
