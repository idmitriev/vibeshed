import Foundation

struct GitHubConfig: Codable, Sendable, Equatable {
    /// Personal Access Token (ghp_xxx). Optional — without one (and without the GitHub
    /// CLI's login, see `useGitHubCLI`) search is limited to public repos at 10 searches
    /// a minute; with one it's 30 a minute and private repos too.
    var token: String?

    /// Default owner/org scope. When set, prepends "org:{defaultOwner}"
    /// to search queries that don't already contain a qualifier.
    var defaultOwner: String?

    /// Owners/orgs to fetch repos from. When nil or empty, falls back
    /// to [defaultOwner] (if set) or the authenticated user's repos.
    var repoOwners: [String]?

    /// Maximum results returned per search type (1–100).
    var maxResults: Int = 10

    /// Which top-level search types to surface: "repo", "issue", "pr".
    var searchTypes: [String] = ["repo", "issue", "pr"]

    /// Set of action name suffixes to expose (nil = all).
    var enabledActions: Set<String>?

    /// Show "My Repositories" listing action (requires token or defaultOwner).
    var showRepos: Bool = true

    /// Show unread notifications action (requires token).
    var showNotifications: Bool = true

    /// Use the GitHub CLI's login (`gh auth token`) when `token` is unset.
    var useGitHubCLI: Bool = true

    /// Where `gh` is, when it isn't in /opt/homebrew/bin or /usr/local/bin.
    var ghPath: String?

    /// List your open pull requests in the main search, refreshed in the background.
    /// Without a token they're the open pull requests in `repoOwners` (or `defaultOwner`).
    var showPullRequests: Bool = true

    /// Which open pull requests are yours, by GitHub's search qualifiers: author,
    /// review-requested, assignee, involves, mentions.
    var pullRequestFilters: [String] = ["author", "review-requested"]

    /// Most pull requests listed per filter (1–100).
    var maxPullRequests: Int = 50

    /// Seconds a listing stays fresh; the next picker open after that refreshes it (30–3600).
    var pullRequestRefresh: Int = 120
}

extension GitHubConfig {
    /// Every key is optional: a missing one keeps its default above instead of failing
    /// the whole section (see `ApplicationConfig`).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        token = try container.decodeIfPresent(String.self, forKey: .token)
        defaultOwner = try container.decodeIfPresent(String.self, forKey: .defaultOwner)
        repoOwners = try container.decodeIfPresent([String].self, forKey: .repoOwners)
        maxResults = try container.decodeIfPresent(Int.self, forKey: .maxResults) ?? defaults.maxResults
        searchTypes = try container.decodeIfPresent([String].self, forKey: .searchTypes) ?? defaults.searchTypes
        enabledActions = try container.decodeIfPresent(Set<String>.self, forKey: .enabledActions)
        showRepos = try container.decodeIfPresent(Bool.self, forKey: .showRepos) ?? defaults.showRepos
        showNotifications = try container.decodeIfPresent(Bool.self, forKey: .showNotifications)
            ?? defaults.showNotifications
        useGitHubCLI = try container.decodeIfPresent(Bool.self, forKey: .useGitHubCLI) ?? defaults.useGitHubCLI
        ghPath = try container.decodeIfPresent(String.self, forKey: .ghPath)
        showPullRequests = try container.decodeIfPresent(Bool.self, forKey: .showPullRequests)
            ?? defaults.showPullRequests
        pullRequestFilters = try container.decodeIfPresent([String].self, forKey: .pullRequestFilters)
            ?? defaults.pullRequestFilters
        maxPullRequests = try container.decodeIfPresent(Int.self, forKey: .maxPullRequests)
            ?? defaults.maxPullRequests
        pullRequestRefresh = try container.decodeIfPresent(Int.self, forKey: .pullRequestRefresh)
            ?? defaults.pullRequestRefresh
    }

    /// The filters that parse, in config order.
    var resolvedPullRequestFilters: [GitHubPullRequestFilter] {
        pullRequestFilters.compactMap(GitHubPullRequestFilter.init(rawValue:))
    }
}
