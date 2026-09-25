import Foundation
import OSLog

private let log = Log.module("spotify")

// MARK: - Search Result Types

struct SpotifyTrack: Sendable {
    let id: String
    let name: String
    let artistName: String
    let albumName: String
    let artworkURL: String?
    let durationMs: Int
    let uri: String
}

struct SpotifyAlbum: Sendable {
    let id: String
    let name: String
    let artistName: String
    let artworkURL: String?
    let uri: String
}

struct SpotifyArtist: Sendable {
    let id: String
    let name: String
    let artworkURL: String?
    let uri: String
}

struct SpotifyPlaylist: Sendable {
    let id: String
    let name: String
    let ownerName: String
    let artworkURL: String?
    let trackCount: Int
    let uri: String
}

struct SpotifySearchResults: Sendable {
    let tracks: [SpotifyTrack]
    let albums: [SpotifyAlbum]
    let artists: [SpotifyArtist]
    let playlists: [SpotifyPlaylist]
}

// MARK: - Response Parsing

/// Maps Spotify Web API search JSON onto the result types, skipping items that lack required fields.
enum SpotifyResponseParser {
    static func parseSearchResults(_ data: Data, types: [String]) throws -> SpotifySearchResults {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            log.error("Failed to parse Spotify search response as JSON")
            throw SpotifySearchClient.SearchError.parseFailed
        }

        let tracks: [SpotifyTrack] = types.contains("track")
            ? parseItems(json["tracks"], parser: parseTrack) : []
        let albums: [SpotifyAlbum] = types.contains("album")
            ? parseItems(json["albums"], parser: parseAlbum) : []
        let artists: [SpotifyArtist] = types.contains("artist")
            ? parseItems(json["artists"], parser: parseArtist) : []
        let playlists: [SpotifyPlaylist] = types.contains("playlist")
            ? parseItems(json["playlists"], parser: parsePlaylist) : []

        return SpotifySearchResults(
            tracks: tracks, albums: albums, artists: artists, playlists: playlists
        )
    }

    private static func parseItems<T>(_ container: Any?, parser: ([String: Any]) -> T?) -> [T] {
        guard let dict = container as? [String: Any],
              let items = dict["items"] as? [[String: Any]]
        else { return [] }
        return items.compactMap(parser)
    }

    private static func parseTrack(_ item: [String: Any]) -> SpotifyTrack? {
        guard let id = item["id"] as? String,
              let name = item["name"] as? String,
              let uri = item["uri"] as? String
        else { return nil }
        let artists = item["artists"] as? [[String: Any]] ?? []
        let artistName = artists.first?["name"] as? String ?? "Unknown Artist"
        let album = item["album"] as? [String: Any]
        let albumName = album?["name"] as? String ?? ""
        let artworkURL = firstImageURL(from: album)
        let durationMs = item["duration_ms"] as? Int ?? 0
        return SpotifyTrack(
            id: id, name: name, artistName: artistName, albumName: albumName,
            artworkURL: artworkURL, durationMs: durationMs, uri: uri
        )
    }

    private static func parseAlbum(_ item: [String: Any]) -> SpotifyAlbum? {
        guard let id = item["id"] as? String,
              let name = item["name"] as? String,
              let uri = item["uri"] as? String
        else { return nil }
        let artists = item["artists"] as? [[String: Any]] ?? []
        let artistName = artists.first?["name"] as? String ?? "Unknown Artist"
        let artworkURL = firstImageURL(from: item)
        return SpotifyAlbum(
            id: id, name: name, artistName: artistName, artworkURL: artworkURL, uri: uri
        )
    }

    private static func parseArtist(_ item: [String: Any]) -> SpotifyArtist? {
        guard let id = item["id"] as? String,
              let name = item["name"] as? String,
              let uri = item["uri"] as? String
        else { return nil }
        let artworkURL = firstImageURL(from: item)
        return SpotifyArtist(id: id, name: name, artworkURL: artworkURL, uri: uri)
    }

    private static func parsePlaylist(_ item: [String: Any]) -> SpotifyPlaylist? {
        guard let id = item["id"] as? String,
              let name = item["name"] as? String,
              let uri = item["uri"] as? String
        else { return nil }
        let owner = item["owner"] as? [String: Any]
        let ownerName = owner?["display_name"] as? String ?? "Unknown"
        let artworkURL = firstImageURL(from: item)
        let tracks = item["tracks"] as? [String: Any]
        let trackCount = tracks?["total"] as? Int ?? 0
        return SpotifyPlaylist(
            id: id, name: name, ownerName: ownerName,
            artworkURL: artworkURL, trackCount: trackCount, uri: uri
        )
    }

    private static func firstImageURL(from container: Any?) -> String? {
        guard let dict = container as? [String: Any],
              let images = dict["images"] as? [[String: Any]],
              let first = images.first,
              let url = first["url"] as? String
        else { return nil }
        return url
    }
}
