import AppKit
import Foundation
import OSLog

private let log = Log.module("spotify")

/// `spotify_cli`, the command-line tool Spotify bundles inside its app (undocumented;
/// there since 1.3). It searches, plays and edits the library through the running
/// desktop app with the user's own login, so none of it needs a Web API client ID —
/// and none of it works while the app isn't running.
struct SpotifyCLI: Sendable {
    let executableURL: URL

    /// The tool inside the installed Spotify.app; nil when Spotify is missing or predates it.
    static func locate() -> SpotifyCLI? {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: SpotifyManager.bundleID)
        else { return nil }
        let url = app.appendingPathComponent("Contents/MacOS/spotify_cli")
        return FileManager.default.isExecutableFile(atPath: url.path) ? SpotifyCLI(executableURL: url) : nil
    }

    /// The tool's results for `query`, up to `limitPerType` of each of `types`, ranked
    /// the way the Spotify app's own search ranks them.
    func search(_ query: String, types: [String], limitPerType: Int) async throws -> [SpotifySearchItem] {
        // The query has to come straight after `search`, and one starting with a dash
        // reads as a flag (there's no `--`); Spotify ignores the leading space.
        var arguments = ["search", query.hasPrefix("-") ? " " + query : query]
        // One request covers every type: the limit is shared among them.
        arguments += ["--limit", String(min(limitPerType * types.count, Self.maxSearchLimit))]
        if types.count == 1, let type = types.first {
            arguments += ["--type", type]
        }
        let output = try await run(arguments + ["--format", "json"])
        return try SpotifyCLIParser.searchItems(output, types: types, limitPerType: limitPerType)
    }

    /// Plays a song, or an album, artist or playlist from its start.
    func play(_ uri: String) async throws {
        try await run(["play", uri])
    }

    func isInLibrary(_ uri: String) async throws -> Bool {
        let output = try await run(["library", "contains", uri, "--format", "json"])
        return try SpotifyCLIParser.contains(output, uri: uri)
    }

    func addToLibrary(_ uri: String) async throws {
        try await run(["library", "add", uri])
    }

    func removeFromLibrary(_ uri: String) async throws {
        try await run(["library", "remove", uri])
    }

    /// Waits until the app is up and signed in, as it is a few seconds after launching.
    func waitUntilReady(timeout: Duration) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let output = try? await run(["status", "--format", "json"]),
               SpotifyCLIParser.isReady(output)
            {
                return
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw SpotifyCLIError.notRunning
    }

    /// The most results one search returns.
    static let maxSearchLimit = 50

    // MARK: - Running

    @discardableResult
    private func run(_ arguments: [String], timeout: TimeInterval = 10) async throws -> Data {
        let executableURL = executableURL
        return try await withCheckedThrowingContinuation { continuation in
            let gate = ResumeGate(continuation: continuation)
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executableURL
                process.arguments = arguments
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                let timeoutWorkItem = DispatchWorkItem {
                    log.warning("spotify_cli \(arguments.first ?? "", privacy: .public) timed out")
                    gate.resume(with: .failure(SpotifyCLIError.timedOut))
                    process.terminate()
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

                do {
                    try process.run()
                } catch {
                    timeoutWorkItem.cancel()
                    gate.resume(with: .failure(error))
                    return
                }

                // Drain both pipes before waiting on exit (see AppleScriptRunner.run):
                // a full pipe buffer would otherwise block the tool forever.
                let readGroup = DispatchGroup()
                // Safe: readGroup.wait() below is a happens-before barrier against both writes.
                nonisolated(unsafe) var outputData = Data()
                nonisolated(unsafe) var errorData = Data()
                readGroup.enter()
                DispatchQueue.global(qos: .utility).async {
                    outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    readGroup.leave()
                }
                readGroup.enter()
                DispatchQueue.global(qos: .utility).async {
                    errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    readGroup.leave()
                }
                readGroup.wait()
                process.waitUntilExit()
                timeoutWorkItem.cancel()

                guard process.terminationStatus == 0 else {
                    let message = String(data: errorData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    log.warning(
                        "spotify_cli \(arguments.first ?? "", privacy: .public) failed: \(message, privacy: .public)"
                    )
                    gate.resume(with: .failure(SpotifyCLIError(message: message)))
                    return
                }
                gate.resume(with: .success(outputData))
            }
        }
    }
}

enum SpotifyCLIError: LocalizedError, Equatable {
    case notRunning
    case timedOut
    case failed(String)

    /// The tool says "Spotify desktop client is not running" when that's the trouble.
    init(message: String) {
        self = message.localizedCaseInsensitiveContains("not running") ? .notRunning : .failed(message)
    }

    var errorDescription: String? {
        switch self {
        case .notRunning: "Spotify isn't running"
        case .timedOut: "Spotify didn't answer in time"
        case let .failed(message): message.isEmpty ? "Spotify's command-line tool failed" : message
        }
    }
}

// MARK: - Output Parsing

enum SpotifyCLIParser {
    /// `search --format json`: a list per type (`tracks`, `albums`, …), `categories_order`
    /// ranking the types for the query, and Spotify's own playlists for it under
    /// `top_recommendations`, which join the playlists. Each type keeps up to
    /// `limitPerType` results, deduplicated by URI.
    static func searchItems(_ data: Data, types: [String], limitPerType: Int) throws -> [SpotifySearchItem] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let output = try decoder.decode(SearchOutput.self, from: data)
        let ranked = (output.categoriesOrder ?? []).map { String($0.dropLast()) }.filter(types.contains)
        let order = ranked + types.filter { !ranked.contains($0) }

        var seen: Set<String> = []
        return order.flatMap { type -> [SpotifySearchItem] in
            guard let kind = SpotifyItemType.searchable[type] else { return [] }
            var entries = output.entries(type)
            if kind == .playlist {
                entries += output.topRecommendations?.playlists ?? []
            }
            let items = entries.compactMap { $0.item(kind: kind) }.filter { seen.insert($0.uri).inserted }
            return Array(items.prefix(limitPerType))
        }
    }

    /// `library contains <uri> --format json`: `{"contains": {"<uri>": true}}`.
    static func contains(_ data: Data, uri: String) throws -> Bool {
        guard let output = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contains = output["contains"] as? [String: Bool]
        else { throw SpotifyCLIError.failed("Unexpected output from spotify_cli library contains") }
        return contains[uri] ?? false
    }

    /// `status --format json`: `{"running": true, "logged_in": true}`.
    static func isReady(_ data: Data) -> Bool {
        guard let status = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        return status["running"] as? Bool == true && status["logged_in"] as? Bool == true
    }

    private struct SearchOutput: Decodable {
        let tracks: [Entry]?
        let albums: [Entry]?
        let artists: [Entry]?
        let playlists: [Entry]?
        let topRecommendations: Recommendations?
        let categoriesOrder: [String]?

        func entries(_ type: String) -> [Entry] {
            switch type {
            case "track": tracks ?? []
            case "album": albums ?? []
            case "artist": artists ?? []
            case "playlist": playlists ?? []
            default: []
            }
        }
    }

    private struct Recommendations: Decodable {
        let playlists: [Entry]?
    }

    private struct Entry: Decodable {
        let uri: String?
        let name: String?
        let artists: [String]?
        let author: String?
        let image: String?

        func item(kind: SpotifyItemType) -> SpotifySearchItem? {
            guard let uri, let name, !name.isEmpty else { return nil }
            let artworkURL = SpotifyArtwork.url(image)
            return SpotifySearchItem(
                uri: uri,
                kind: kind,
                name: name,
                byline: artists?.joined(separator: ", ") ?? author ?? "",
                artworkURL: artworkURL,
                previewArtworkURL: SpotifyArtwork.larger(artworkURL)
            )
        }
    }
}
