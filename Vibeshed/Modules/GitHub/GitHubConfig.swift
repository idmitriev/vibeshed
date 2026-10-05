import Foundation

struct GitHubConfig: Codable, Sendable, Equatable {
    /// Personal Access Token (ghp_xxx). Optional — unauthenticated search
    /// gives 60 requests/hr; authenticated gives 5000 requests/hr.
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
    }
}
