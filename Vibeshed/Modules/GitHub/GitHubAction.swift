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
    let itemDescription: String?
    let labels: [String]?
    let createdAt: String?
    let repoStars: Int?
    let repoLanguage: String?
    /// Set on the open pull requests listed in the main search, which get their own preview.
    let pullRequest: GitHubPullRequest?
    let requiresWordPrefixMatch: Bool
    let deduplicationKey: String?

    private let runner: @Sendable (ParameterValues) async throws -> ActionResult

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
        itemDescription: String? = nil,
        labels: [String]? = nil,
        createdAt: String? = nil,
        repoStars: Int? = nil,
        repoLanguage: String? = nil,
        pullRequest: GitHubPullRequest? = nil,
        requiresWordPrefixMatch: Bool = false,
        deduplicationKey: String? = nil,
        runner: @escaping @Sendable (ParameterValues) async throws -> ActionResult
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
        self.itemDescription = itemDescription
        self.labels = labels
        self.createdAt = createdAt
        self.repoStars = repoStars
        self.repoLanguage = repoLanguage
        self.pullRequest = pullRequest
        self.requiresWordPrefixMatch = requiresWordPrefixMatch
        self.deduplicationKey = deduplicationKey
        self.runner = runner
    }

    func run(with values: ParameterValues) async throws -> ActionResult {
        try await runner(values)
    }

    @MainActor
    func makeListItemView() -> AnyView? {
        AnyView(GitHubActionListItemView(action: self))
    }

    @MainActor
    func makePreviewView() -> AnyView? {
        if let pullRequest {
            return AnyView(GitHubPullRequestPreviewView(action: self, pullRequest: pullRequest))
        }
        return AnyView(GitHubActionPreviewView(action: self))
    }
}
