import Foundation

struct BrowserConfig: Codable, Sendable, Equatable {
    /// Which browsers to query. Empty means all running supported browsers.
    var browsers: [String] = []

    /// How many seconds to cache tab listings before re-querying.
    var cacheTTLSeconds: Double = 3.0

    /// Maximum number of tabs to show in results (0 = unlimited).
    var maxResults: Int = 0

    /// Whether to show "Close Tab" actions alongside focus actions.
    var showCloseActions: Bool = true
}
