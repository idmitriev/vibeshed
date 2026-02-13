import Foundation

struct GitHubConfig: Codable, Sendable, Equatable {
    /// Personal Access Token (ghp_xxx). Optional — unauthenticated search
    /// gives 60 requests/hr; authenticated gives 5000 requests/hr.
    var token: String?

    /// Default owner/org scope. When set, prepends "org:{defaultOwner}"
    /// to search queries that don't already contain a qualifier.
    var defaultOwner: String?

    /// Maximum results returned per search type (1–100).
    var maxResults: Int = 10

    /// Which top-level search types to surface: "repo", "issue", "pr".
    var searchTypes: [String] = ["repo", "issue", "pr"]

    /// Set of action name suffixes to expose (nil = all).
    var enabledActions: Set<String>?

    /// Show unread notifications action (requires token).
    var showNotifications: Bool = true
}
