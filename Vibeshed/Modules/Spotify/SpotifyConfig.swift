import Foundation

struct SpotifyConfig: Codable, Sendable, Equatable {
    /// Spotify Web API client ID. Search and Like go through the `spotify_cli` tool inside
    /// Spotify.app and need none; with an older Spotify that lacks the tool, they use the
    /// Web API with this ID, and without it only playback actions are available.
    var clientId: String?

    /// Max search results of each type (1-50). The Web API returns at most 10 of each,
    /// and `spotify_cli` at most 100 in all.
    var maxSearchResults: Int = 10

    /// What types to search: "track", "album", "artist", "playlist".
    var searchTypes: [String] = ["track", "album", "artist", "playlist"]

    /// Actions to include (nil = all). Action names match the suffix after "spotify.".
    var enabledActions: Set<String>?

    /// Whether to show "Now Playing" as an action when Spotify is running.
    var showNowPlaying: Bool = true
}

extension SpotifyConfig {
    /// Every key is optional: a missing one keeps its default above instead of failing
    /// the whole section (see `ApplicationConfig`).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        clientId = try container.decodeIfPresent(String.self, forKey: .clientId)
        maxSearchResults = try container.decodeIfPresent(Int.self, forKey: .maxSearchResults)
            ?? defaults.maxSearchResults
        searchTypes = try container.decodeIfPresent([String].self, forKey: .searchTypes) ?? defaults.searchTypes
        enabledActions = try container.decodeIfPresent(Set<String>.self, forKey: .enabledActions)
        showNowPlaying = try container.decodeIfPresent(Bool.self, forKey: .showNowPlaying) ?? defaults.showNowPlaying
    }
}
