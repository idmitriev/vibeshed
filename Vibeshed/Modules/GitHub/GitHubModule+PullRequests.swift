import Foundation
import SwiftUI

/// Where the module's token came from.
enum GitHubCredentialSource: String, Sendable {
    case config
    case githubCLI = "GitHub CLI"
    case none
}

// MARK: - Reloading

extension GitHubModule {
    /// After a failed listing, the next picker open this long after tries again, unless
    /// `pullRequestRefresh` is shorter or the rate limit resets later.
    static let pullRequestRetryInterval: TimeInterval = 30

    /// Resolves the token, then lists repos and pull requests, all in the background.
    /// Work still running for the previous config is dropped.
    func reload() {
        configGeneration += 1
        let generation = configGeneration
        reloadTask?.cancel()
        pullRequestTask?.cancel()
        pullRequestTask = nil
        credentialsStale = false
        if let token = config.token {
            // A configured token needs no lookup, so searches built from here on use it.
            setCredentials(GitHubAPIClient(token: token), source: .config)
        }
        reloadTask = Task { [self] in
            await resolveCredentials(generation: generation)
            guard generation == configGeneration else { return }
            if config.showPullRequests {
                refreshPullRequests()
            } else if listing != .empty {
                listing = .empty
            }
            await fetchRepos()
            guard generation == configGeneration else { return }
            reloadTask = nil
            // Search actions carry the client they were built with, and repo rows may
            // have changed, so the picker fetches the catalog again.
            await publishActionsChanged()
        }
    }

    /// The configured token, else the GitHub CLI's, else none.
    private func resolveCredentials(generation: Int) async {
        if config.token != nil { return }
        let token = config.useGitHubCLI ? await tokenReader(config.ghPath) : nil
        guard generation == configGeneration else { return }
        if let token {
            setCredentials(GitHubAPIClient(token: token), source: .githubCLI)
        } else {
            setCredentials(GitHubAPIClient(token: nil), source: .none)
        }
    }

    private func setCredentials(_ client: GitHubAPIClient, source: GitHubCredentialSource) {
        apiClient = client
        credentialSource = source
        log.info("GitHub requests authenticated by: \(source.rawValue, privacy: .public)")
    }

    func publishActionsChanged() async {
        await context?.eventBus.publish(.moduleActionsChanged(moduleID: id))
    }
}

// MARK: - Open Pull Requests

extension GitHubModule {
    /// Starts a refresh when the listing has gone stale. Called on every catalog fetch,
    /// which happens once per picker open.
    func refreshPullRequestsIfDue() {
        guard config.showPullRequests, reloadTask == nil, pullRequestTask == nil else { return }
        if credentialsStale {
            reload()
        } else if isPullRequestRefreshDue {
            refreshPullRequests()
        }
    }

    private var isPullRequestRefreshDue: Bool {
        if let pullRequestRetryAt {
            return Date() >= pullRequestRetryAt
        }
        return Date().timeIntervalSince(pullRequestsListedAt) >= TimeInterval(config.pullRequestRefresh)
    }

    /// Lists open pull requests unless a listing is already under way, and returns it to wait on.
    @discardableResult
    func refreshPullRequests() -> Task<Void, Never> {
        if let pullRequestTask {
            return pullRequestTask
        }
        let client = apiClient
        let config = config
        let generation = configGeneration
        let fetcher = pullRequestFetcher
        let task = Task { [self] in
            let start = ContinuousClock.now
            let result: Result<GitHubPullRequestListing, Error>
            do {
                result = try await .success(fetcher(client, config))
            } catch {
                result = .failure(error)
            }
            await finishPullRequestRefresh(result, generation: generation, took: ContinuousClock.now - start)
        }
        pullRequestTask = task
        return task
    }

    private func finishPullRequestRefresh(
        _ result: Result<GitHubPullRequestListing, Error>,
        generation: Int,
        took: Duration
    ) async {
        // A reload took over (and started its own listing) while this one ran.
        guard generation == configGeneration else { return }
        pullRequestTask = nil
        switch result {
        case let .success(listed):
            pullRequestsListedAt = Date()
            pullRequestRetryAt = nil
            let count = listed.pullRequests.count
            log.debug("Listed \(count, privacy: .public) open pull requests in \(took, privacy: .public)")
            guard listed != listing else { return }
            listing = listed
            await publishActionsChanged()
        case let .failure(error):
            let freshFor = TimeInterval(config.pullRequestRefresh)
            var retryAt = Date().addingTimeInterval(min(freshFor, Self.pullRequestRetryInterval))
            if case let GitHubError.rateLimited(resetDate?) = error {
                retryAt = max(retryAt, resetDate)
            }
            if case GitHubError.invalidToken = error, credentialSource == .githubCLI {
                // Signed out of gh, or signed in again with a new token: ask gh again.
                credentialsStale = true
            }
            pullRequestRetryAt = retryAt
            log.error("Failed to list open pull requests: \(error.localizedDescription, privacy: .public)")
        }
    }

    func pullRequestActions() -> [GitHubAction] {
        guard config.showPullRequests else { return [] }
        let viewer = listing.viewer
        let eventBus = context?.eventBus
        return listing.pullRequests.enumerated().map { index, pullRequest in
            Self.pullRequestAction(pullRequest, index: index, viewer: viewer, eventBus: eventBus)
        }
    }

    /// The open pull requests of `config`: the user's own (by `pullRequestFilters`) when
    /// requests go as them, else those in the repos of `repoOwners` or `defaultOwner`.
    static func fetchOpenPullRequests(
        client: GitHubAPIClient,
        config: GitHubConfig
    ) async throws -> GitHubPullRequestListing {
        if client.hasToken {
            return try await client.openPullRequests(
                filters: config.resolvedPullRequestFilters, limit: config.maxPullRequests
            )
        }
        return try await client.openPullRequests(owners: pullRequestOwners(config), limit: config.maxPullRequests)
    }

    static func pullRequestOwners(_ config: GitHubConfig) -> [String] {
        if let owners = config.repoOwners, !owners.isEmpty {
            return owners
        }
        return config.defaultOwner.map { [$0] } ?? []
    }

    static func pullRequestErrors(_ config: GitHubConfig) -> [String] {
        var errors: [String] = []
        if !(1 ... 100).contains(config.maxPullRequests) {
            errors.append("maxPullRequests must be between 1 and 100")
        }
        if !(30 ... 3600).contains(config.pullRequestRefresh) {
            errors.append("pullRequestRefresh must be between 30 and 3600 seconds")
        }
        let valid = GitHubPullRequestFilter.allCases.map(\.rawValue).joined(separator: ", ")
        for filter in config.pullRequestFilters where GitHubPullRequestFilter(rawValue: filter) == nil {
            errors.append("Invalid pull request filter: '\(filter)'. Valid: \(valid)")
        }
        if config.showPullRequests, config.pullRequestFilters.isEmpty {
            errors.append("pullRequestFilters must not be empty; set showPullRequests: false to hide pull requests")
        }
        if let ghPath = config.ghPath, ghPath.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("ghPath must not be empty when specified")
        }
        return errors
    }
}

// MARK: - Rows

extension GitHubModule {
    static func pullRequestActionID(_ pullRequest: GitHubPullRequest) -> ActionID {
        ActionID(module: "github", name: "pr.\(StableID.hash(pullRequest.key))")
    }

    /// One open pull request in the main search. It matches only on whole-word prefixes
    /// (`requiresWordPrefixMatch`), so "satis" finds "Make the website satisfying" while
    /// "sa" stays with Safari. Newest update first, all below apps' relevance.
    static func pullRequestAction(
        _ pullRequest: GitHubPullRequest,
        index: Int,
        viewer: String?,
        eventBus: EventBus?
    ) -> GitHubAction {
        let url = pullRequest.url
        let branchWords = WordPrefixMatch.words(in: [pullRequest.headBranch].compactMap { $0 })
        return GitHubAction(
            id: pullRequestActionID(pullRequest),
            title: pullRequest.title,
            subtitle: pullRequestSubtitle(pullRequest, viewer: viewer),
            iconName: "arrow.triangle.pull",
            relevanceScore: max(0.4, 0.55 - Double(index) * 0.005),
            // Branch words, which the title and subtitle don't show; no "pr" or "pull",
            // whose exact-keyword bonus would put every row above "Preview".
            keywords: branchWords,
            avatarURL: pullRequest.avatarURL,
            githubItemType: .pr,
            htmlURL: url,
            stateIcon: pullRequest.isDraft ? "doc" : "arrow.triangle.pull",
            stateColor: pullRequest.isDraft ? .gray : .green,
            pullRequest: pullRequest,
            requiresWordPrefixMatch: true,
            // One row with an open browser tab of the same pull request.
            deduplicationKey: ActionScorer.normalizeURL(url)
        ) { [eventBus] _ in
            await openURL(url, via: eventBus)
            return .dismiss
        }
    }

    /// `owner/repo #12`, then the author when it isn't the user, then what most needs
    /// attention: "idmitriev/vibeshed #81 · Checks failing".
    static func pullRequestSubtitle(_ pullRequest: GitHubPullRequest, viewer: String?) -> String {
        var parts = ["\(pullRequest.repository) #\(pullRequest.number)"]
        if let viewer, pullRequest.author.caseInsensitiveCompare(viewer) != .orderedSame {
            parts.append("by \(pullRequest.author)")
        }
        if let status = pullRequestStatus(pullRequest) {
            parts.append(status)
        }
        return parts.joined(separator: " · ")
    }

    static func pullRequestStatus(_ pullRequest: GitHubPullRequest) -> String? {
        if pullRequest.isDraft {
            return "Draft"
        }
        if pullRequest.matchedFilters.contains(.reviewRequested) {
            return "Review requested"
        }
        if pullRequest.checks == .failing {
            return "Checks failing"
        }
        switch pullRequest.reviewDecision {
        case .changesRequested: return "Changes requested"
        case .approved: return "Approved"
        case .reviewRequired, nil: return nil
        }
    }
}
