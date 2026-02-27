import AuthenticationServices
import CryptoKit
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

// MARK: - Search Client

final class SpotifySearchClient: @unchecked Sendable {
    private let clientId: String
    private let redirectURI = "vibeshed://spotify-callback"
    private let lock = NSLock()
    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiry: Date = .distantPast
    private let tokenFileURL: URL

    init(clientId: String) {
        self.clientId = clientId
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/vibeshed")
        self.tokenFileURL = configDir.appendingPathComponent("spotify-tokens.json")
        loadTokens()
    }

    // MARK: - Public

    func isAuthenticated() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return accessToken != nil
    }

    func search(
        query: String,
        types: [String],
        limit: Int
    ) async throws -> SpotifySearchResults {
        try await ensureAuthenticated()

        let token: String = {
            lock.lock()
            defer { lock.unlock() }
            return accessToken ?? ""
        }()

        guard !token.isEmpty else {
            log.error("Search called but no access token available")
            throw SearchError.notAuthenticated
        }

        let typeParam = types.joined(separator: ",")
        guard let encodedQuery = query.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) else {
            throw SearchError.invalidQuery
        }

        let urlString =
            "https://api.spotify.com/v1/search?q=\(encodedQuery)&type=\(typeParam)&limit=\(limit)"
        guard let url = URL(string: urlString) else {
            throw SearchError.invalidQuery
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 401 {
                log.debug("Spotify API returned 401, refreshing token")
                try await refreshAccessToken()
                return try await search(query: query, types: types, limit: limit)
            }
            guard (200 ... 299).contains(httpResponse.statusCode) else {
                log.error("Spotify API error: HTTP \(httpResponse.statusCode, privacy: .public)")
                throw SearchError.apiError(httpResponse.statusCode)
            }
        }

        return try parseSearchResults(data, types: types)
    }

    // MARK: - Library

    func isTrackSaved(_ trackId: String) async throws -> Bool {
        try await ensureAuthenticated()
        let token = lockedToken()
        guard !token.isEmpty else { throw SearchError.notAuthenticated }

        let url = URL(string: "https://api.spotify.com/v1/me/tracks/contains?ids=\(trackId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            try await refreshAccessToken()
            return try await isTrackSaved(trackId)
        }
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw SearchError.apiError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard let results = try JSONSerialization.jsonObject(with: data) as? [Bool],
              let isSaved = results.first
        else { return false }
        return isSaved
    }

    func saveTrack(_ trackId: String) async throws {
        try await modifyLibrary(trackId: trackId, method: "PUT")
    }

    func removeSavedTrack(_ trackId: String) async throws {
        try await modifyLibrary(trackId: trackId, method: "DELETE")
    }

    private func modifyLibrary(trackId: String, method: String) async throws {
        try await ensureAuthenticated()
        let token = lockedToken()
        guard !token.isEmpty else { throw SearchError.notAuthenticated }

        let url = URL(string: "https://api.spotify.com/v1/me/tracks?ids=\(trackId)")!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            try await refreshAccessToken()
            try await modifyLibrary(trackId: trackId, method: method)
            return
        }
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw SearchError.apiError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    private func lockedToken() -> String {
        lock.lock()
        defer { lock.unlock() }
        return accessToken ?? ""
    }

    // MARK: - Authentication

    func ensureAuthenticated() async throws {
        let needsRefresh: Bool = {
            lock.lock()
            defer { lock.unlock() }
            if accessToken == nil { return false }
            return Date() >= tokenExpiry
        }()

        if needsRefresh {
            try await refreshAccessToken()
            return
        }

        let hasToken: Bool = {
            lock.lock()
            defer { lock.unlock() }
            return accessToken != nil
        }()

        if !hasToken {
            try await authenticate()
        }
    }

    // MARK: - Private: OAuth PKCE

    private func authenticate() async throws {
        log.debug("Starting Spotify OAuth PKCE flow")
        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(verifier: verifier)

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "user-read-playback-state user-modify-playback-state user-library-read user-library-modify"),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
        ]

        guard let authURL = components.url else {
            log.error("Failed to construct Spotify auth URL")
            throw SearchError.authFailed("Invalid auth URL")
        }

        let callbackURL = try await performAuthSession(url: authURL)

        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            let error = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "error" })?.value ?? "no code"
            log.error("Spotify OAuth callback error: \(error, privacy: .public)")
            throw SearchError.authFailed(error)
        }

        try await exchangeCodeForTokens(code: code, verifier: verifier)
    }

    @MainActor
    private func performAuthSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "vibeshed"
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: SearchError.authFailed(error.localizedDescription))
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: SearchError.authFailed("No callback URL"))
                }
            }
            session.presentationContextProvider = WebAuthContextProvider.shared
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    private func exchangeCodeForTokens(code: String, verifier: String) async throws {
        let url = URL(string: "https://accounts.spotify.com/api/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type=authorization_code",
            "code=\(code)",
            "redirect_uri=\(redirectURI)",
            "client_id=\(clientId)",
            "code_verifier=\(verifier)",
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            log.error("Spotify token exchange failed")
            throw SearchError.authFailed("Token exchange failed")
        }

        try parseAndStoreTokens(data)
        log.debug("Spotify token exchange succeeded")
    }

    private func refreshAccessToken() async throws {
        log.debug("Refreshing Spotify access token")
        let currentRefresh: String? = {
            lock.lock()
            defer { lock.unlock() }
            return refreshToken
        }()

        guard let refreshToken = currentRefresh else {
            log.debug("No refresh token, starting fresh auth")
            try await authenticate()
            return
        }

        let url = URL(string: "https://accounts.spotify.com/api/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type=refresh_token",
            "refresh_token=\(refreshToken)",
            "client_id=\(clientId)",
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            log.warning("Spotify token refresh failed, clearing tokens and re-authenticating")
            lock.lock()
            self.accessToken = nil
            self.refreshToken = nil
            lock.unlock()
            saveTokens()
            try await authenticate()
            return
        }

        try parseAndStoreTokens(data)
    }

    // MARK: - Private: Token Management

    private func parseAndStoreTokens(_ data: Data) throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let expiresIn = json["expires_in"] as? Int
        else {
            log.error("Invalid token response from Spotify")
            throw SearchError.authFailed("Invalid token response")
        }

        lock.lock()
        self.accessToken = accessToken
        if let newRefresh = json["refresh_token"] as? String {
            self.refreshToken = newRefresh
        }
        self.tokenExpiry = Date().addingTimeInterval(TimeInterval(expiresIn - 60))
        lock.unlock()

        saveTokens()
    }

    private func loadTokens() {
        guard let data = try? Data(contentsOf: tokenFileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            log.debug("No saved Spotify tokens found")
            return
        }
        log.debug("Loaded Spotify tokens from disk")

        lock.lock()
        accessToken = json["accessToken"] as? String
        refreshToken = json["refreshToken"] as? String
        if let expiry = json["expiresAt"] as? TimeInterval {
            tokenExpiry = Date(timeIntervalSince1970: expiry)
        }
        lock.unlock()
    }

    private func saveTokens() {
        lock.lock()
        let json: [String: Any] = [
            "accessToken": accessToken as Any,
            "refreshToken": refreshToken as Any,
            "expiresAt": tokenExpiry.timeIntervalSince1970,
        ]
        lock.unlock()

        guard let data = try? JSONSerialization.data(withJSONObject: json) else {
            log.warning("Failed to serialize Spotify tokens for saving")
            return
        }
        do {
            try data.write(to: tokenFileURL, options: .atomic)
        } catch {
            log.warning("Failed to save Spotify tokens: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Private: PKCE Helpers

    private func generateCodeVerifier() -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        return String((0 ..< 64).map { _ in chars.randomElement()! })
    }

    private func generateCodeChallenge(verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Private: Response Parsing

    private func parseSearchResults(_ data: Data, types: [String]) throws -> SpotifySearchResults {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            log.error("Failed to parse Spotify search response as JSON")
            throw SearchError.parseFailed
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

    private func parseItems<T>(_ container: Any?, parser: ([String: Any]) -> T?) -> [T] {
        guard let dict = container as? [String: Any],
              let items = dict["items"] as? [[String: Any]]
        else { return [] }
        return items.compactMap(parser)
    }

    private func parseTrack(_ item: [String: Any]) -> SpotifyTrack? {
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

    private func parseAlbum(_ item: [String: Any]) -> SpotifyAlbum? {
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

    private func parseArtist(_ item: [String: Any]) -> SpotifyArtist? {
        guard let id = item["id"] as? String,
              let name = item["name"] as? String,
              let uri = item["uri"] as? String
        else { return nil }
        let artworkURL = firstImageURL(from: item)
        return SpotifyArtist(id: id, name: name, artworkURL: artworkURL, uri: uri)
    }

    private func parsePlaylist(_ item: [String: Any]) -> SpotifyPlaylist? {
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

    private func firstImageURL(from container: Any?) -> String? {
        guard let dict = container as? [String: Any],
              let images = dict["images"] as? [[String: Any]],
              let first = images.first,
              let url = first["url"] as? String
        else { return nil }
        return url
    }

    // MARK: - Errors

    enum SearchError: Error, LocalizedError {
        case notAuthenticated
        case invalidQuery
        case apiError(Int)
        case authFailed(String)
        case parseFailed

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: "Not authenticated with Spotify"
            case .invalidQuery: "Invalid search query"
            case .apiError(let code): "Spotify API error (HTTP \(code))"
            case .authFailed(let reason): "Spotify auth failed: \(reason)"
            case .parseFailed: "Failed to parse Spotify response"
            }
        }
    }
}

// MARK: - Auth Presentation Context

@MainActor
private final class WebAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthContextProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
}
