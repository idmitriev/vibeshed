import Foundation
import OSLog

actor SpotifyModule: ModuleConfigurable {
    let id = "spotify"
    let displayName = "Spotify"
    let iconName = "music.note"
    var isEnabled = true

    typealias Config = SpotifyConfig
    static var defaultConfig: Config? { .init() }

    static var requiredPermissions: Set<Permission> { [.automation] }

    private var config: SpotifyConfig = .init()
    private var context: ModuleContext?
    private var searchClient: SpotifySearchClient?
    private let log = Log.module("spotify")

    func initialize(context: ModuleContext) async throws {
        self.context = context
        updateSearchClient()
        log.info("Spotify module initialized (searchClient: \(self.searchClient != nil ? "enabled" : "disabled"))")
    }

    func configDidUpdate(_ config: SpotifyConfig) async {
        let oldClientId = self.config.clientId
        self.config = config
        if config.clientId != oldClientId {
            updateSearchClient()
            log.info("Search client updated (clientId changed)")
        }
    }

    static func validate(_ config: SpotifyConfig) -> ConfigValidationResult {
        var errors: [String] = []

        if let clientId = config.clientId,
           clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("clientId must not be empty when specified")
        }
        if config.maxSearchResults < 1 || config.maxSearchResults > 50 {
            errors.append("maxSearchResults must be between 1 and 50")
        }
        let validTypes: Set<String> = ["track", "album", "artist", "playlist"]
        for searchType in config.searchTypes {
            if !validTypes.contains(searchType) {
                errors.append("Invalid search type: '\(searchType)'. Valid: track, album, artist, playlist")
            }
        }
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    func provideActions(query: String, scoring: ScoringContext) async -> [any Action] {
        let actions = await buildActions()

        guard !query.isEmpty else { return actions }
        let lowered = query.lowercased()
        return actions.filter { action in
            action.title.lowercased().contains(lowered)
                || action.subtitle.lowercased().contains(lowered)
                || action.keywords.contains { $0.contains(lowered) }
        }
    }

    // MARK: - Private

    private func updateSearchClient() {
        if let clientId = config.clientId,
           !clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            searchClient = SpotifySearchClient(clientId: clientId)
        } else {
            searchClient = nil
        }
    }

    private func buildActions() async -> [SpotifyAction] {
        let enabled = config.enabledActions
        var actions: [SpotifyAction] = []

        if config.showNowPlaying {
            if let action = await buildNowPlayingAction() {
                actions.append(action)
            }
        }

        if SpotifyManager.isRunning() {
            actions.append(contentsOf: buildPlaybackActions())
        }

        actions.append(contentsOf: buildSearchActions())

        if let enabled {
            return actions.filter { enabled.contains(actionName($0.id)) }
        }
        return actions
    }

    private func actionName(_ id: ActionID) -> String {
        let raw = id.rawValue
        guard let dotIndex = raw.firstIndex(of: ".") else { return raw }
        return String(raw[raw.index(after: dotIndex)...])
    }

    // MARK: - Now Playing

    private func buildNowPlayingAction() async -> SpotifyAction? {
        guard SpotifyManager.isRunning(),
              let np = try? await SpotifyManager.nowPlaying()
        else { return nil }

        let stateIcon = np.isPlaying ? "pause.circle" : "play.circle"
        return SpotifyAction(
            id: ActionID(module: "spotify", name: "nowPlaying"),
            title: np.trackName,
            subtitle: "\(np.artistName) — \(np.albumName)",
            iconName: stateIcon,
            relevanceScore: 0.95,
            keywords: [
                "spotify", "now", "playing", "current", "track",
                np.trackName.lowercased(), np.artistName.lowercased(),
            ],
            artworkURL: np.artworkURL,
            spotifyItemType: .nowPlaying
        ) { _ in
            try await SpotifyManager.playPause()
            return .dismiss
        }
    }

    // MARK: - Playback Actions

    private func buildPlaybackActions() -> [SpotifyAction] {
        [
            SpotifyAction(
                id: ActionID(module: "spotify", name: "playPause"),
                title: "Play / Pause",
                subtitle: "Toggle Spotify playback",
                iconName: "playpause",
                relevanceScore: 0.9,
                keywords: ["spotify", "play", "pause", "music", "media"],
                spotifyItemType: .control
            ) { _ in
                try await SpotifyManager.playPause()
                return .dismiss
            },
            SpotifyAction(
                id: ActionID(module: "spotify", name: "next"),
                title: "Next Track",
                subtitle: "Skip to next track in Spotify",
                iconName: "forward.end",
                relevanceScore: 0.85,
                keywords: ["spotify", "next", "skip", "forward", "track"],
                spotifyItemType: .control
            ) { _ in
                try await SpotifyManager.nextTrack()
                return .dismiss
            },
            SpotifyAction(
                id: ActionID(module: "spotify", name: "previous"),
                title: "Previous Track",
                subtitle: "Go to previous track in Spotify",
                iconName: "backward.end",
                relevanceScore: 0.85,
                keywords: ["spotify", "previous", "back", "rewind", "track"],
                spotifyItemType: .control
            ) { _ in
                try await SpotifyManager.previousTrack()
                return .dismiss
            },
            SpotifyAction(
                id: ActionID(module: "spotify", name: "shuffle"),
                title: "Toggle Shuffle",
                subtitle: "Toggle shuffle mode in Spotify",
                iconName: "shuffle",
                relevanceScore: 0.7,
                keywords: ["spotify", "shuffle", "random"],
                spotifyItemType: .control
            ) { _ in
                try await SpotifyManager.toggleShuffle()
                return .dismiss
            },
            SpotifyAction(
                id: ActionID(module: "spotify", name: "repeat"),
                title: "Toggle Repeat",
                subtitle: "Toggle repeat mode in Spotify",
                iconName: "repeat",
                relevanceScore: 0.7,
                keywords: ["spotify", "repeat", "loop"],
                spotifyItemType: .control
            ) { _ in
                try await SpotifyManager.toggleRepeat()
                return .dismiss
            },
        ]
    }

    // MARK: - Search Actions

    private func buildSearchActions() -> [SpotifyAction] {
        var actions: [SpotifyAction] = []

        if let client = searchClient {
            let config = self.config
            actions.append(SpotifyAction(
                id: ActionID(module: "spotify", name: "search"),
                title: "Search Spotify",
                subtitle: "Search tracks, albums, artists, playlists",
                iconName: "magnifyingglass",
                relevanceScore: 0.9,
                keywords: ["spotify", "search", "find", "music"],
                parameters: [
                    ActionParameter(
                        id: "query",
                        label: "Search Query",
                        type: .text(placeholder: "Search tracks, albums, artists..."),
                        isRequired: true
                    ),
                ],
                spotifyItemType: .control
            ) { [client, config] values in
                guard let query = values["query"] as? String, !query.isEmpty else {
                    return .showResult(title: "Search", body: "Please enter a search query")
                }
                let results = try await client.search(
                    query: query,
                    types: config.searchTypes,
                    limit: config.maxSearchResults
                )
                let resultActions = Self.buildSearchResultActions(results)
                if resultActions.isEmpty {
                    return .showResult(title: "No Results", body: "No results for \"\(query)\"")
                }
                return .pushActions(resultActions)
            })
        }

        actions.append(SpotifyAction(
            id: ActionID(module: "spotify", name: "quickSearch"),
            title: "Open Spotify Search",
            subtitle: "Search in Spotify app",
            iconName: "magnifyingglass",
            relevanceScore: searchClient != nil ? 0.6 : 0.85,
            keywords: ["spotify", "search", "find", "open"],
            parameters: [
                ActionParameter(
                    id: "query",
                    label: "Search Query",
                    type: .text(placeholder: "Search in Spotify..."),
                    isRequired: true
                ),
            ],
            spotifyItemType: .control
        ) { values in
            let query = values["query"] as? String ?? ""
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            try await SpotifyManager.openURI("spotify:search:\(encoded)")
            return .dismiss
        })

        return actions
    }

    // MARK: - Search Result Actions

    private static func buildSearchResultActions(
        _ results: SpotifySearchResults
    ) -> [SpotifyAction] {
        var actions: [SpotifyAction] = []
        actions.append(contentsOf: buildTrackResults(results.tracks))
        actions.append(contentsOf: buildAlbumResults(results.albums))
        actions.append(contentsOf: buildArtistResults(results.artists))
        actions.append(contentsOf: buildPlaylistResults(results.playlists))
        return actions
    }

    private static func buildTrackResults(_ tracks: [SpotifyTrack]) -> [SpotifyAction] {
        tracks.enumerated().map { index, track in
            SpotifyAction(
                id: ActionID(module: "spotify", name: "result.track.\(track.id)"),
                title: track.name,
                subtitle: "\(track.artistName) — \(track.albumName)",
                iconName: "music.note",
                relevanceScore: max(0.3, 0.95 - Double(index) * 0.02),
                keywords: ["track", track.name.lowercased(), track.artistName.lowercased()],
                artworkURL: track.artworkURL,
                spotifyItemType: .track
            ) { _ in
                try await SpotifyManager.openURI(track.uri)
                return .dismiss
            }
        }
    }

    private static func buildAlbumResults(_ albums: [SpotifyAlbum]) -> [SpotifyAction] {
        albums.enumerated().map { index, album in
            SpotifyAction(
                id: ActionID(module: "spotify", name: "result.album.\(album.id)"),
                title: album.name,
                subtitle: album.artistName,
                iconName: "square.stack",
                relevanceScore: max(0.3, 0.90 - Double(index) * 0.02),
                keywords: ["album", album.name.lowercased(), album.artistName.lowercased()],
                artworkURL: album.artworkURL,
                spotifyItemType: .album
            ) { _ in
                try await SpotifyManager.openURI(album.uri)
                return .dismiss
            }
        }
    }

    private static func buildArtistResults(_ artists: [SpotifyArtist]) -> [SpotifyAction] {
        artists.enumerated().map { index, artist in
            SpotifyAction(
                id: ActionID(module: "spotify", name: "result.artist.\(artist.id)"),
                title: artist.name,
                subtitle: "Artist",
                iconName: "person",
                relevanceScore: max(0.3, 0.88 - Double(index) * 0.02),
                keywords: ["artist", artist.name.lowercased()],
                artworkURL: artist.artworkURL,
                spotifyItemType: .artist
            ) { _ in
                try await SpotifyManager.openURI(artist.uri)
                return .dismiss
            }
        }
    }

    private static func buildPlaylistResults(_ playlists: [SpotifyPlaylist]) -> [SpotifyAction] {
        playlists.enumerated().map { index, playlist in
            SpotifyAction(
                id: ActionID(module: "spotify", name: "result.playlist.\(playlist.id)"),
                title: playlist.name,
                subtitle: "by \(playlist.ownerName) · \(playlist.trackCount) tracks",
                iconName: "music.note.list",
                relevanceScore: max(0.3, 0.85 - Double(index) * 0.02),
                keywords: ["playlist", playlist.name.lowercased(), playlist.ownerName.lowercased()],
                artworkURL: playlist.artworkURL,
                spotifyItemType: .playlist
            ) { _ in
                try await SpotifyManager.openURI(playlist.uri)
                return .dismiss
            }
        }
    }
}
