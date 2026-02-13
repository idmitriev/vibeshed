import SwiftUI

enum GitHubItemType: String, Sendable {
    case repo
    case issue
    case pr
    case notification
}

struct GitHubAction: Action {
    let id: ActionID
    let title: String
    let subtitle: String
    let iconName: String?
    let relevanceScore: Double
    let keywords: [String]
    let parameters: [ActionParameter]

    let avatarURL: String?
    let githubItemType: GitHubItemType?
    let htmlURL: String?
    let stateIcon: String?
    let stateColor: Color?

    private let runner: @Sendable ([String: Any]) async throws -> ActionResult

    init(
        id: ActionID,
        title: String,
        subtitle: String,
        iconName: String? = nil,
        relevanceScore: Double = 0.8,
        keywords: [String] = [],
        parameters: [ActionParameter] = [],
        avatarURL: String? = nil,
        githubItemType: GitHubItemType? = nil,
        htmlURL: String? = nil,
        stateIcon: String? = nil,
        stateColor: Color? = nil,
        runner: @escaping @Sendable ([String: Any]) async throws -> ActionResult
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.relevanceScore = relevanceScore
        self.keywords = keywords
        self.parameters = parameters
        self.avatarURL = avatarURL
        self.githubItemType = githubItemType
        self.htmlURL = htmlURL
        self.stateIcon = stateIcon
        self.stateColor = stateColor
        self.runner = runner
    }

    func run(with values: [String: Any]) async throws -> ActionResult {
        try await runner(values)
    }

    @MainActor
    func makeListItemView() -> AnyView? {
        AnyView(GitHubActionListItemView(action: self))
    }

    @MainActor
    func makePreviewView() -> AnyView? {
        AnyView(GitHubActionPreviewView(action: self))
    }
}
