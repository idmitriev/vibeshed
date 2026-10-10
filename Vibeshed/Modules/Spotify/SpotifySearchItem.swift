import Foundation
import OSLog

private let log = Log.module("spotify")

// MARK: - Search Item

/// One search result — a song, album, artist or playlist — from either source
/// (`spotify_cli` or the Web API). Playing it plays its URI.
struct SpotifySearchItem: Sendable, Equatable {
    let uri: String
    let kind: SpotifyItemType
    let name: String
    /// Artists for songs and albums, the owner for playlists; empty for artists.
    let byline: String
    /// The small cover the result list shows.
    let artworkURL: URL?
    /// A larger copy for the preview panel, when there is one.
    let previewArtworkURL: URL?

    /// "Song · Radiohead"
    var subtitle: String {
        byline.isEmpty ? kind.searchLabel : "\(kind.searchLabel) · \(byline)"
    }
}

extension SpotifyItemType {
    /// The kinds `searchTypes` can name, by their Web API / CLI type name.
    static let searchable: [String: SpotifyItemType] = [
        "track": .track, "album": .album, "artist": .artist, "playlist": .playlist,
    ]

    /// What the Spotify app calls the kind in its own search results.
    var searchLabel: String {
        switch self {
        case .track: "Song"
        case .album: "Album"
        case .artist: "Artist"
        case .playlist: "Playlist"
        case .nowPlaying: "Now Playing"
        case .control: "Control"
        }
    }

    var iconName: String {
        switch self {
        case .track: "music.note"
        case .album: "square.stack"
        case .artist: "person"
        case .playlist: "music.note.list"
        case .nowPlaying: "waveform"
        case .control: "playpause"
        }
    }

    /// "Song, album, artist or playlist" for the configured search types.
    static func searchPrompt(for types: [String]) -> String {
        let labels = types.compactMap { searchable[$0]?.searchLabel.lowercased() }
        guard let last = labels.last else { return "Search Spotify" }
        let sentence = labels.count == 1 ? last : labels.dropLast().joined(separator: ", ") + " or " + last
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }
}

// MARK: - Artwork

enum SpotifyArtwork {
    /// `spotify:image:<id>`, as `spotify_cli` names covers, on Spotify's image CDN;
    /// https URLs (some playlist covers) as they are.
    static func url(_ value: String?) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        let imagePrefix = "spotify:image:"
        if value.hasPrefix(imagePrefix) {
            return URL(string: "https://i.scdn.co/image/" + value.dropFirst(imagePrefix.count))
        }
        return value.hasPrefix("https://") ? URL(string: value) : nil
    }

    /// The CDN serves each cover at a few sizes, coded in the start of its id, and the
    /// CLI hands out the smallest: 64px album covers and 160px artist photos. These are
    /// the 300px and 320px copies; other images stay as they are.
    static func larger(_ url: URL?) -> URL? {
        guard let url else { return nil }
        let string = url.absoluteString
        for (small, large) in largerSizes {
            let prefix = "https://i.scdn.co/image/" + small
            if string.hasPrefix(prefix) {
                return URL(string: "https://i.scdn.co/image/" + large + string.dropFirst(prefix.count))
            }
        }
        return url
    }

    private static let largerSizes = [
        ("ab67616d00004851", "ab67616d00001e02"),
        ("ab6761610000f178", "ab67616100005174"),
    ]
}

// MARK: - Web API Response Parsing

/// Maps Spotify Web API search JSON onto search items, in `types` order, skipping
/// items that lack required fields.
enum SpotifyResponseParser {
    static func parseSearchResults(_ data: Data, types: [String]) throws -> [SpotifySearchItem] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            log.error("Failed to parse Spotify search response as JSON")
            throw SpotifySearchClient.SearchError.parseFailed
        }
        return types.flatMap { type -> [SpotifySearchItem] in
            guard let kind = SpotifyItemType.searchable[type],
                  let container = json[type + "s"] as? [String: Any],
                  // Playlist searches list removed playlists as nulls among the items.
                  let items = container["items"] as? [Any]
            else { return [] }
            return items.compactMap { ($0 as? [String: Any]).flatMap { parseItem($0, kind: kind) } }
        }
    }

    private static func parseItem(_ item: [String: Any], kind: SpotifyItemType) -> SpotifySearchItem? {
        guard let name = item["name"] as? String,
              let uri = item["uri"] as? String
        else { return nil }
        let byline: String = switch kind {
        case .track, .album:
            (item["artists"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
                .joined(separator: ", ")
        case .playlist:
            (item["owner"] as? [String: Any])?["display_name"] as? String ?? ""
        default:
            ""
        }
        // Images come largest first; a song's are its album's.
        let images = ((kind == .track ? item["album"] : item) as? [String: Any])?["images"] as? [[String: Any]] ?? []
        let urls = images.compactMap { ($0["url"] as? String).flatMap(URL.init(string:)) }
        return SpotifySearchItem(
            uri: uri, kind: kind, name: name, byline: byline,
            artworkURL: urls.last, previewArtworkURL: urls.first
        )
    }
}
