import Foundation

struct BookmarkConfig: Codable, Sendable, Equatable {
    /// Which browsers to read bookmarks from. Empty means all installed supported browsers.
    var browsers: [String] = []

    /// Maximum number of bookmark actions to show in the picker (0 = unlimited).
    var maxBookmarks: Int = 100

    /// Maximum number of most-visited history entries to show.
    var maxVisited: Int = 30

    /// Whether to show most-visited history actions.
    var showMostVisited: Bool = true

    /// Minimum visit count to include a history entry.
    var minVisitCount: Int = 3

    /// How many seconds to cache bookmark/history data before re-reading.
    var cacheTTLSeconds: Double = 300
}
