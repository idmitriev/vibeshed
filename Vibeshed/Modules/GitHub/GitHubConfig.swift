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
