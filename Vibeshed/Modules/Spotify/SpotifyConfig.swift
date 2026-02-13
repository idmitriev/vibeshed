import Foundation

struct SpotifyConfig: Codable, Sendable, Equatable {
    /// Spotify API client ID for Web API search. If nil, only playback actions are available.
    var clientId: String?

    /// Max search results to return from Web API (1-50).
    var maxSearchResults: Int = 10

    /// What types to search: "track", "album", "artist", "playlist".
    var searchTypes: [String] = ["track", "album", "artist", "playlist"]

    /// Actions to include (nil = all). Action names match the suffix after "spotify.".
    var enabledActions: Set<String>?

    /// Whether to show "Now Playing" as an action when Spotify is running.
    var showNowPlaying: Bool = true
}
