import AppKit
import Foundation
import OSLog
import SwiftUI

actor GitHubModule: ModuleConfigurable {
    let id = "github"
    let displayName = "GitHub"
    let iconName = "chevron.left.forwardslash.chevron.right"
    var isEnabled = true

    typealias Config = GitHubConfig
    static var defaultConfig: Config? {
        .init()
    }

    private var config: GitHubConfig = .init()
    private var context: ModuleContext?
    private var apiClient: GitHubAPIClient = .init(token: nil)
    private var cachedRepos: [GitHubRepo] = []
    private let log = Log.module("github")

    func initialize(context: ModuleContext) async throws {
        self.context = context
        updateAPIClient()
        await fetchRepos()
        let tokenState = config.token != nil ? "configured" : "none"
        log.info("GitHub module initialized (token: \(tokenState, privacy: .public))")
    }

    func configDidUpdate(_ config: GitHubConfig) async {
        let oldToken = self.config.token
        let oldOwner = self.config.defaultOwner
        let oldRepoOwners = self.config.repoOwners
        let oldShowRepos = self.config.showRepos
        self.config = config
        if config.token != oldToken {
            updateAPIClient()
            log.info("API client updated (token changed)")
        }
        if config.token != oldToken || config.defaultOwner != oldOwner
            || config.repoOwners != oldRepoOwners || config.showRepos != oldShowRepos
        {
            await fetchRepos()
        }
    }

    static func validate(
        _ config: GitHubConfig
    ) -> ConfigValidationResult {
        var errors: [String] = []

        if let token = config.token,
           token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            errors.append("token must not be empty when specified")
        }
        if config.maxResults < 1 || config.maxResults > 100 {
            errors.append("maxResults must be between 1 and 100")
        }
        let validTypes: Set<String> = ["repo", "issue", "pr"]
        for searchType in config.searchTypes where !validTypes.contains(searchType) {
            let valid = validTypes.sorted().joined(separator: ", ")
            errors.append(
                "Invalid search type: '\(searchType)'. Valid: \(valid)"
            )
        }
        if let owners = config.repoOwners {
            for (index, owner) in owners.enumerated()
                where owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                errors.append("repoOwners[\(index)] must not be empty")
            }
            if Set(owners).count < owners.count {
                errors.append("repoOwners contains duplicate entries")
            }
        }
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    func provideActions(
        query: String,
        scoring: ScoringContext
    ) async -> [any Action] {
        buildActions()
    }

    // MARK: - Private

    private func updateAPIClient() {
        apiClient = GitHubAPIClient(token: config.token)
    }

    /// Resolved owners for repo fetching.
    /// Falls back: repoOwners → [defaultOwner] → [nil] (authenticated user).
    private var resolvedRepoOwners: [String?] {
        if let owners = config.repoOwners, !owners.isEmpty {
            return owners.map { Optional($0) }
        }
        return [config.defaultOwner]
    }

    private func fetchRepos() async {
        let owners = resolvedRepoOwners
        guard config.showRepos,
              config.token != nil || owners.contains(where: { $0 != nil })
        else {
            cachedRepos = []
            return
        }

        let perOwnerLimit = max(1, config.maxResults / max(1, owners.count))
        var allRepos: [GitHubRepo] = []
        var seenIDs: Set<Int> = []

        for owner in owners {
            do {
                let repos = try await apiClient.listRepos(
                    owner: owner,
                    limit: perOwnerLimit
                )
                for repo in repos where !seenIDs.contains(repo.id) {
                    seenIDs.insert(repo.id)
                    allRepos.append(repo)
                }
            } catch {
                let label = owner ?? "authenticated-user"
                let reason = error.localizedDescription
                log.error("Failed to fetch repos for '\(label, privacy: .public)': \(reason, privacy: .public)")
            }
        }

        cachedRepos = Array(allRepos.prefix(config.maxResults))
        let repoCount = cachedRepos.count
        log.info("Fetched \(repoCount, privacy: .public) repos from \(owners.count, privacy: .public) owner(s)")
    }

    private func actionName(_ id: ActionID) -> String {
        id.actionName
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
            actions = actions.filter { enabled.contains(actionName($0.id)) }
        }

        // Repo actions are always included (gated by showRepos, not enabledActions)
        if config.showRepos, !cachedRepos.isEmpty {
            let eventBus = context?.eventBus
            actions.append(contentsOf: Self.buildRepoResults(cachedRepos, eventBus: eventBus))
        }

        return actions
    }
}

// MARK: - Search Actions

extension GitHubModule {
    private func buildSearchAction() -> GitHubAction {
        let client = apiClient
        let config = self.config
        let eventBus = context?.eventBus
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
        ) { [client, config, eventBus] values in
            guard let query = values["query"],
                  !query.isEmpty
            else {
                return .showResult(
                    title: "Search GitHub",
                    body: "Please enter a search query"
                )
            }
            let resultActions = try await Self.searchAllTypes(
                query: query, client: client, config: config, eventBus: eventBus
            )
            if resultActions.isEmpty {
                return .showResult(
                    title: "No Results",
                    body: "No GitHub results for \"\(query)\""
                )
            }
            return .pushActions(resultActions)
        }
    }

    /// Runs one search per configured type, splitting `maxResults` evenly between them.
    private static func searchAllTypes(
        query: String,
        client: GitHubAPIClient,
        config: GitHubConfig,
        eventBus: EventBus?
    ) async throws -> [GitHubAction] {
        let owner = config.defaultOwner
        let typeCount = max(1, config.searchTypes.count)
        let limit = max(1, config.maxResults / typeCount)
        var resultActions: [GitHubAction] = []

        if config.searchTypes.contains("repo") {
            let repos = try await client.searchRepos(
                query: query, defaultOwner: owner, limit: limit
            )
            resultActions.append(
                contentsOf: buildRepoResults(repos, eventBus: eventBus)
            )
        }
        if config.searchTypes.contains("issue") {
            let issues = try await client.searchIssues(
                query: query, defaultOwner: owner, limit: limit
            )
            resultActions.append(
                contentsOf: buildIssueResults(issues, eventBus: eventBus)
            )
        }
        if config.searchTypes.contains("pr") {
            let prs = try await client.searchPRs(
                query: query, defaultOwner: owner, limit: limit
            )
            resultActions.append(
                contentsOf: buildPRResults(prs, eventBus: eventBus)
            )
        }
        return resultActions
    }

    private func buildSearchReposAction() -> GitHubAction {
        let client = apiClient
        let config = self.config
        let eventBus = context?.eventBus
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
        ) { [client, config, eventBus] values in
            guard let query = values["query"],
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
            let results = Self.buildRepoResults(repos, eventBus: eventBus)
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
        let eventBus = context?.eventBus
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
        ) { [client, config, eventBus] values in
            guard let query = values["query"],
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
            let results = Self.buildIssueResults(issues, eventBus: eventBus)
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
        let eventBus = context?.eventBus
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
        ) { [client, config, eventBus] values in
            guard let query = values["query"],
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
            let results = Self.buildPRResults(prs, eventBus: eventBus)
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
        let eventBus = context?.eventBus
        return GitHubAction(
            id: ActionID(module: "github", name: "notifications"),
            title: "Notifications",
            subtitle: "View unread GitHub notifications",
            iconName: "bell",
            relevanceScore: 0.88,
            keywords: ["github", "notification", "unread", "inbox"]
        ) { [client, config, eventBus] _ in
            let notifications = try await client.listNotifications(
                limit: config.maxResults
            )
            let results = Self.buildNotificationResults(notifications, eventBus: eventBus)
            if results.isEmpty {
                return .showResult(
                    title: "No Notifications",
                    body: "All caught up!"
                )
            }
            return .pushActions(results)
        }
    }
}
