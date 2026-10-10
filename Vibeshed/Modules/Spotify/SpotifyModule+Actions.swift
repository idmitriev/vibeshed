import Foundation

extension SpotifyModule {
    func buildActions() async -> [SpotifyAction] {
        let enabled = config.enabledActions
        let backend = backend
        var actions: [SpotifyAction] = []

        if config.showNowPlaying {
            if let action = await buildNowPlayingAction() {
                actions.append(action)
            }
        }

        if SpotifyManager.isRunning() {
            if let backend {
                actions.append(buildLikeAction(backend))
            }
            actions.append(contentsOf: buildPlaybackActions())
        }

        if backend != nil {
            actions.append(buildSearchAction())
        }
        actions.append(buildQuickSearchAction(hasSearch: backend != nil))

        if let enabled {
            return actions.filter { enabled.contains($0.id.actionName) }
        }
        return actions
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
            spotifyItemType: .nowPlaying,
            durationMs: np.durationMs
        ) { _ in
            try await SpotifyManager.playPause()
            return .dismiss
        }
    }

    // MARK: - Like / Unlike

    private func buildLikeAction(_ backend: Backend) -> SpotifyAction {
        SpotifyAction(
            id: ActionID(module: "spotify", name: "likeTrack"),
            title: "Like / Unlike Current Track",
            subtitle: "Toggle current track in Liked Songs",
            iconName: "heart",
            relevanceScore: 0.8,
            keywords: ["spotify", "like", "unlike", "save", "heart", "favourite", "favorite", "liked"],
            spotifyItemType: .control
        ) { _ in
            // Local files and ads have other kinds of IDs.
            guard let np = try? await SpotifyManager.nowPlaying(),
                  np.trackID.hasPrefix("spotify:track:")
            else {
                return .showResult(title: "No Track", body: "No track is currently playing")
            }

            if try await backend.isInLibrary(np.trackID) {
                try await backend.removeFromLibrary(np.trackID)
                return .showResult(title: "Removed", body: "\(np.trackName) removed from Liked Songs")
            } else {
                try await backend.addToLibrary(np.trackID)
                return .showResult(title: "Liked", body: "\(np.trackName) added to Liked Songs")
            }
        }
    }

    // MARK: - Playback Actions

    private func buildPlaybackActions() -> [SpotifyAction] {
        PlaybackControl.all.map { control in
            SpotifyAction(
                id: ActionID(module: "spotify", name: control.name),
                title: control.title,
                subtitle: control.subtitle,
                iconName: control.iconName,
                relevanceScore: control.relevanceScore,
                keywords: control.keywords,
                spotifyItemType: .control
            ) { _ in
                try await control.command()
                return .dismiss
            }
        }
    }

    // MARK: - Search Actions

    /// Lists results as the query is typed; Return plays the highlighted one.
    private func buildSearchAction() -> SpotifyAction {
        SpotifyAction(
            id: ActionID(module: "spotify", name: "search"),
            title: "Search Spotify",
            subtitle: "Play a song, album, artist or playlist",
            iconName: "magnifyingglass",
            relevanceScore: 0.9,
            keywords: ["spotify", "search", "find", "music", "play", "song", "track", "album", "artist", "playlist"],
            parameters: [
                ActionParameter(
                    id: Self.itemParameterID,
                    label: SpotifyItemType.searchPrompt(for: config.searchTypes),
                    type: .dynamicSelection(hint: "result"),
                    isRequired: true,
                    rankedByModule: true
                ),
            ],
            spotifyItemType: .control
        ) { values in
            guard let optionID = values[Self.itemParameterID] else { return .keepOpen }
            return try await self.playResult(optionID)
        }
    }

    private func buildQuickSearchAction(hasSearch: Bool) -> SpotifyAction {
        SpotifyAction(
            id: ActionID(module: "spotify", name: "quickSearch"),
            title: "Open Spotify Search",
            subtitle: "Search in Spotify app",
            iconName: "magnifyingglass",
            relevanceScore: hasSearch ? 0.6 : 0.85,
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
            let query = values["query"] ?? ""
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            try await SpotifyManager.navigate(to: "spotify:search:\(encoded)")
            return .dismiss
        }
    }
}

// MARK: - Playback Controls

/// Transport controls offered while Spotify is running.
private struct PlaybackControl: Sendable {
    let name: String
    let title: String
    let subtitle: String
    let iconName: String
    let relevanceScore: Double
    let keywords: [String]
    let command: @Sendable () async throws -> Void

    static let all: [PlaybackControl] = [
        PlaybackControl(
            name: "playPause",
            title: "Play / Pause",
            subtitle: "Toggle Spotify playback",
            iconName: "playpause",
            relevanceScore: 0.9,
            keywords: ["spotify", "play", "pause", "music", "media"],
            command: { try await SpotifyManager.playPause() }
        ),
        PlaybackControl(
            name: "next",
            title: "Next Track",
            subtitle: "Skip to next track in Spotify",
            iconName: "forward.end",
            relevanceScore: 0.85,
            keywords: ["spotify", "next", "skip", "forward", "track"],
            command: { try await SpotifyManager.nextTrack() }
        ),
        PlaybackControl(
            name: "previous",
            title: "Previous Track",
            subtitle: "Go to previous track in Spotify",
            iconName: "backward.end",
            relevanceScore: 0.85,
            keywords: ["spotify", "previous", "back", "rewind", "track"],
            command: { try await SpotifyManager.previousTrack() }
        ),
        PlaybackControl(
            name: "shuffle",
            title: "Toggle Shuffle",
            subtitle: "Toggle shuffle mode in Spotify",
            iconName: "shuffle",
            relevanceScore: 0.7,
            keywords: ["spotify", "shuffle", "random"],
            command: { try await SpotifyManager.toggleShuffle() }
        ),
        PlaybackControl(
            name: "repeat",
            title: "Toggle Repeat",
            subtitle: "Toggle repeat mode in Spotify",
            iconName: "repeat",
            relevanceScore: 0.7,
            keywords: ["spotify", "repeat", "loop"],
            command: { try await SpotifyManager.toggleRepeat() }
        ),
    ]
}
