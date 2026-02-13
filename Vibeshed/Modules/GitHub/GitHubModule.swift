import AppKit
import Foundation
import SwiftUI

actor GitHubModule: ModuleConfigurable {
    let id = "github"
    let displayName = "GitHub"
    let iconName = "chevron.left.forwardslash.chevron.right"
    var isEnabled = true

    typealias Config = GitHubConfig
    static var defaultConfig: Config? { .init() }

    private var config: GitHubConfig = .init()
    private var context: ModuleContext?
    private var apiClient: GitHubAPIClient = .init(token: nil)

    func initialize(context: ModuleContext) async throws {
        self.context = context
        updateAPIClient()
    }

    func configDidUpdate(_ config: GitHubConfig) async {
        let oldToken = self.config.token
        self.config = config
        if config.token != oldToken {
            updateAPIClient()
        }
    }

    static func validate(
        _ config: GitHubConfig
    ) -> ConfigValidationResult {
        var errors: [String] = []

        if let token = config.token,
           token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("token must not be empty when specified")
        }
        if config.maxResults < 1 || config.maxResults > 100 {
            errors.append("maxResults must be between 1 and 100")
        }
        let validTypes: Set<String> = ["repo", "issue", "pr"]
        for searchType in config.searchTypes {
            if !validTypes.contains(searchType) {
                let valid = validTypes.sorted().joined(separator: ", ")
                errors.append(
                    "Invalid search type: '\(searchType)'. Valid: \(valid)"
                )
            }
        }
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    func provideActions(
        query: String,
        scoring: ScoringContext
    ) async -> [any Action] {
        let actions = buildActions()

        guard !query.isEmpty else { return actions }
        let lowered = query.lowercased()
        return actions.filter { action in
            action.title.lowercased().contains(lowered)
                || action.subtitle.lowercased().contains(lowered)
                || action.keywords.contains { $0.contains(lowered) }
        }
    }

    // MARK: - Private

    private func updateAPIClient() {
        apiClient = GitHubAPIClient(token: config.token)
    }

    private func actionName(_ id: ActionID) -> String {
        let raw = id.rawValue
        guard let dotIndex = raw.firstIndex(of: ".") else { return raw }
        return String(raw[raw.index(after: dotIndex)...])
    }

    private func buildActions() -> [GitHubAction] {
        let enabled = config.enabledActions
        var actions: [GitHubAction] = []

        actions.append(buildSearchAction())

        if config.searchTypes.contains("repo") {
            actions.append(buildSearchReposAction())
        }
        if config.searchTypes.contains("issue") {
            actions.append(buildSearchIssuesAction())
        }
        if config.searchTypes.contains("pr") {
            actions.append(buildSearchPRsAction())
        }
        if let action = buildNotificationsAction() {
            actions.append(action)
        }

        if let enabled {
            return actions.filter { enabled.contains(actionName($0.id)) }
        }
        return actions
    }

    // MARK: - Search Actions

    private func buildSearchAction() -> GitHubAction {
        let client = apiClient
        let config = self.config
        return GitHubAction(
            id: ActionID(module: "github", name: "search"),
            title: "Search GitHub",
            subtitle: "Search repos, issues, and pull requests",
            iconName: "magnifyingglass",
            relevanceScore: 0.9,
            keywords: ["github", "search", "find", "code"],
            parameters: [
                ActionParameter(
                    id: "query",
                    label: "Search Query",
                    type: .text(
                        placeholder: "Search repos, issues, PRs..."
                    ),
                    isRequired: true
                ),
            ]
        ) { [client, config] values in
            guard let query = values["query"] as? String,
                  !query.isEmpty
            else {
                return .showResult(
                    title: "Search GitHub",
                    body: "Please enter a search query"
                )
            }
            let owner = config.defaultOwner
            let typeCount = max(1, config.searchTypes.count)
            let limit = max(1, config.maxResults / typeCount)
            var resultActions: [GitHubAction] = []

            if config.searchTypes.contains("repo") {
                let repos = try await client.searchRepos(
                    query: query, defaultOwner: owner, limit: limit
                )
                resultActions.append(
                    contentsOf: Self.buildRepoResults(repos)
                )
            }
            if config.searchTypes.contains("issue") {
                let issues = try await client.searchIssues(
                    query: query, defaultOwner: owner, limit: limit
                )
                resultActions.append(
                    contentsOf: Self.buildIssueResults(issues)
                )
            }
            if config.searchTypes.contains("pr") {
                let prs = try await client.searchPRs(
                    query: query, defaultOwner: owner, limit: limit
                )
                resultActions.append(
                    contentsOf: Self.buildPRResults(prs)
                )
            }

            if resultActions.isEmpty {
                return .showResult(
                    title: "No Results",
                    body: "No GitHub results for \"\(query)\""
                )
            }
            return .pushActions(resultActions)
        }
    }

    private func buildSearchReposAction() -> GitHubAction {
        let client = apiClient
        let config = self.config
        return GitHubAction(
            id: ActionID(module: "github", name: "searchRepos"),
            title: "Search Repositories",
            subtitle: "Search GitHub repositories",
            iconName: "folder",
            relevanceScore: 0.85,
            keywords: ["github", "repo", "repository", "search"],
            parameters: [
                ActionParameter(
                    id: "query",
                    label: "Search Query",
                    type: .text(placeholder: "Search repositories..."),
                    isRequired: true
                ),
            ]
        ) { [client, config] values in
            guard let query = values["query"] as? String,
                  !query.isEmpty
            else {
                return .showResult(
                    title: "Search Repos",
                    body: "Please enter a search query"
                )
            }
            let repos = try await client.searchRepos(
                query: query,
                defaultOwner: config.defaultOwner,
                limit: config.maxResults
            )
            let results = Self.buildRepoResults(repos)
            if results.isEmpty {
                return .showResult(
                    title: "No Results",
                    body: "No repositories found for \"\(query)\""
                )
            }
            return .pushActions(results)
        }
    }

    private func buildSearchIssuesAction() -> GitHubAction {
        let client = apiClient
        let config = self.config
        return GitHubAction(
            id: ActionID(module: "github", name: "searchIssues"),
            title: "Search Issues",
            subtitle: "Search GitHub issues",
            iconName: "exclamationmark.circle",
            relevanceScore: 0.85,
            keywords: ["github", "issue", "bug", "search"],
            parameters: [
                ActionParameter(
                    id: "query",
                    label: "Search Query",
                    type: .text(placeholder: "Search issues..."),
                    isRequired: true
                ),
            ]
        ) { [client, config] values in
            guard let query = values["query"] as? String,
                  !query.isEmpty
            else {
                return .showResult(
                    title: "Search Issues",
                    body: "Please enter a search query"
                )
            }
            let issues = try await client.searchIssues(
                query: query,
                defaultOwner: config.defaultOwner,
                limit: config.maxResults
            )
            let results = Self.buildIssueResults(issues)
            if results.isEmpty {
                return .showResult(
                    title: "No Results",
                    body: "No issues found for \"\(query)\""
                )
            }
            return .pushActions(results)
        }
    }

    private func buildSearchPRsAction() -> GitHubAction {
        let client = apiClient
        let config = self.config
        return GitHubAction(
            id: ActionID(module: "github", name: "searchPRs"),
            title: "Search Pull Requests",
            subtitle: "Search GitHub pull requests",
            iconName: "arrow.triangle.pull",
            relevanceScore: 0.85,
            keywords: ["github", "pr", "pull", "request", "search"],
            parameters: [
                ActionParameter(
                    id: "query",
                    label: "Search Query",
                    type: .text(placeholder: "Search pull requests..."),
                    isRequired: true
                ),
            ]
        ) { [client, config] values in
            guard let query = values["query"] as? String,
                  !query.isEmpty
            else {
                return .showResult(
                    title: "Search PRs",
                    body: "Please enter a search query"
                )
            }
            let prs = try await client.searchPRs(
                query: query,
                defaultOwner: config.defaultOwner,
                limit: config.maxResults
            )
            let results = Self.buildPRResults(prs)
            if results.isEmpty {
                return .showResult(
                    title: "No Results",
                    body: "No pull requests found for \"\(query)\""
                )
            }
            return .pushActions(results)
        }
    }

    private func buildNotificationsAction() -> GitHubAction? {
        guard config.showNotifications, config.token != nil else {
            return nil
        }
        let client = apiClient
        let config = self.config
        return GitHubAction(
            id: ActionID(module: "github", name: "notifications"),
            title: "Notifications",
            subtitle: "View unread GitHub notifications",
            iconName: "bell",
            relevanceScore: 0.88,
            keywords: ["github", "notification", "unread", "inbox"]
        ) { [client, config] _ in
            let notifications = try await client.listNotifications(
                limit: config.maxResults
            )
            let results = Self.buildNotificationResults(notifications)
            if results.isEmpty {
                return .showResult(
                    title: "No Notifications",
                    body: "All caught up!"
                )
            }
            return .pushActions(results)
        }
    }

    // MARK: - Result Actions

    private static func buildRepoResults(
        _ repos: [GitHubRepo]
    ) -> [GitHubAction] {
        repos.enumerated().map { index, repo in
            let subtitle = repoSubtitle(repo)
            return GitHubAction(
                id: ActionID(
                    module: "github",
                    name: "result.repo.\(repo.id)"
                ),
                title: repo.fullName,
                subtitle: subtitle,
                iconName: "folder",
                relevanceScore: max(0.3, 0.95 - Double(index) * 0.03),
                keywords: [
                    "repo", repo.fullName.lowercased(),
                    repo.language?.lowercased(),
                ].compactMap { $0 },
                avatarURL: repo.avatarURL,
                githubItemType: .repo,
                htmlURL: repo.htmlURL
            ) { _ in
                openURL(repo.htmlURL)
                return .dismiss
            }
        }
    }

    private static func buildIssueResults(
        _ issues: [GitHubIssue]
    ) -> [GitHubAction] {
        issues.enumerated().map { index, issue in
            let (icon, color) = issueStateVisuals(issue.state)
            return GitHubAction(
                id: ActionID(
                    module: "github",
                    name: "result.issue.\(issue.id)"
                ),
                title: "#\(issue.number) \(issue.title)",
                subtitle: "\(issue.repoFullName) by \(issue.author)",
                iconName: "exclamationmark.circle",
                relevanceScore: max(0.3, 0.95 - Double(index) * 0.03),
                keywords: [
                    "issue", issue.title.lowercased(),
                    issue.repoFullName.lowercased(),
                ],
                avatarURL: issue.avatarURL,
                githubItemType: .issue,
                htmlURL: issue.htmlURL,
                stateIcon: icon,
                stateColor: color
            ) { _ in
                openURL(issue.htmlURL)
                return .dismiss
            }
        }
    }

    private static func buildPRResults(
        _ prs: [GitHubPR]
    ) -> [GitHubAction] {
        prs.enumerated().map { index, pr in
            let (icon, color) = prStateVisuals(pr)
            return GitHubAction(
                id: ActionID(
                    module: "github",
                    name: "result.pr.\(pr.id)"
                ),
                title: "#\(pr.number) \(pr.title)",
                subtitle: "\(pr.repoFullName) by \(pr.author)",
                iconName: "arrow.triangle.pull",
                relevanceScore: max(0.3, 0.95 - Double(index) * 0.03),
                keywords: [
                    "pr", "pull", pr.title.lowercased(),
                    pr.repoFullName.lowercased(),
                ],
                avatarURL: pr.avatarURL,
                githubItemType: .pr,
                htmlURL: pr.htmlURL,
                stateIcon: icon,
                stateColor: color
            ) { _ in
                openURL(pr.htmlURL)
                return .dismiss
            }
        }
    }

    private static func buildNotificationResults(
        _ notifications: [GitHubNotification]
    ) -> [GitHubAction] {
        notifications.enumerated().map { index, note in
            let icon = notificationIcon(note.type)
            return GitHubAction(
                id: ActionID(
                    module: "github",
                    name: "result.notification.\(note.id)"
                ),
                title: note.title,
                subtitle: "\(note.repoFullName) · \(note.reason)",
                iconName: icon,
                relevanceScore: max(0.3, 0.95 - Double(index) * 0.03),
                keywords: [
                    "notification", note.title.lowercased(),
                    note.repoFullName.lowercased(),
                ],
                githubItemType: .notification,
                htmlURL: note.htmlURL
            ) { _ in
                if let htmlURL = note.htmlURL {
                    openURL(htmlURL)
                }
                return .dismiss
            }
        }
    }

    // MARK: - Helpers

    @Sendable
    private static func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        DispatchQueue.main.async {
            NSWorkspace.shared.open(url)
        }
    }

    private static func repoSubtitle(_ repo: GitHubRepo) -> String {
        var parts: [String] = []
        if let desc = repo.description, !desc.isEmpty {
            let truncated = desc.prefix(60)
            parts.append(
                truncated.count < desc.count
                    ? "\(truncated)..." : String(truncated)
            )
        }
        if let lang = repo.language {
            parts.append(lang)
        }
        if repo.stars > 0 {
            parts.append("\(formatCount(repo.stars)) stars")
        }
        return parts.joined(separator: " · ")
    }

    private static func formatCount(_ count: Int) -> String {
        if count >= 1000 {
            let k = Double(count) / 1000.0
            return String(format: "%.1fk", k)
        }
        return "\(count)"
    }

    private static func issueStateVisuals(
        _ state: String
    ) -> (String, Color) {
        switch state {
        case "open": ("circle.fill", .green)
        case "closed": ("checkmark.circle.fill", .purple)
        default: ("circle", .secondary)
        }
    }

    private static func prStateVisuals(
        _ pr: GitHubPR
    ) -> (String, Color) {
        if pr.mergedAt != nil {
            return ("arrow.triangle.merge", .purple)
        }
        if pr.state == "closed" {
            return ("xmark.circle.fill", .red)
        }
        if pr.draft {
            return ("doc", .gray)
        }
        return ("arrow.triangle.pull", .green)
    }

    private static func notificationIcon(_ type: String) -> String {
        switch type {
        case "PullRequest": "arrow.triangle.pull"
        case "Issue": "exclamationmark.circle"
        case "Release": "tag"
        case "Discussion": "bubble.left.and.bubble.right"
        default: "bell"
        }
    }
}
