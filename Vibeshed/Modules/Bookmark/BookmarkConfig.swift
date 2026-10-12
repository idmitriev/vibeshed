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

extension BookmarkConfig {
    /// Every key is optional: a missing one keeps its default above instead of failing
    /// the whole section (see `ApplicationConfig`).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        browsers = try container.decodeIfPresent([String].self, forKey: .browsers) ?? defaults.browsers
        maxBookmarks = try container.decodeIfPresent(Int.self, forKey: .maxBookmarks) ?? defaults.maxBookmarks
        maxVisited = try container.decodeIfPresent(Int.self, forKey: .maxVisited) ?? defaults.maxVisited
        showMostVisited = try container.decodeIfPresent(Bool.self, forKey: .showMostVisited)
            ?? defaults.showMostVisited
        minVisitCount = try container.decodeIfPresent(Int.self, forKey: .minVisitCount) ?? defaults.minVisitCount
        cacheTTLSeconds = try container.decodeIfPresent(Double.self, forKey: .cacheTTLSeconds)
            ?? defaults.cacheTTLSeconds
    }
}
