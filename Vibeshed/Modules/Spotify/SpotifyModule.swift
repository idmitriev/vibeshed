import Foundation
import OSLog
import SwiftUI

actor SpotifyModule: ModuleConfigurable {
    let id = "spotify"
    let displayName = "Spotify"
    let iconName = "music.note"
    var isEnabled = true

    typealias Config = SpotifyConfig
    static var defaultConfig: Config? {
        .init()
    }

    var automationTargets: [String] {
        [SpotifyManager.bundleID]
    }

    /// The search action's parameter: the picked result's URI.
    static let itemParameterID = "item"
    /// Shorter queries list nothing yet.
    static let minimumQueryLength = 2
    /// How long typing has to pause before a search runs; each one starts a process.
    static let searchDelay: Duration = .milliseconds(200)
    /// How long Spotify gets to start up and sign in before a search or play gives up.
    static let launchTimeout: Duration = .seconds(20)
    private static let messageOptionID = "message:search"

    private(set) var config: SpotifyConfig = .init()
    private(set) var searchClient: SpotifySearchClient?
    let log = Log.module("spotify")
    /// Finds `spotify_cli`; tests hand in their own.
    private let locateCLI: @Sendable () -> SpotifyCLI?
    private var searchGeneration = 0
    /// The launch in progress, shared by every search and play waiting on it.
    private var launching: Task<Void, Error>?
    /// The latest search error, for the message row that reports it.
    private var lastSearchError: String?

    init(locateCLI: @escaping @Sendable () -> SpotifyCLI? = SpotifyCLI.locate) {
        self.locateCLI = locateCLI
    }

    func initialize(context: ModuleContext) async throws {
        updateSearchClient()
        let source = switch backend {
        case .cli: "spotify_cli"
        case .webAPI: "Web API"
        case nil: "none"
        }
        log.info("Spotify module initialized (search: \(source, privacy: .public))")
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
           clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            errors.append("clientId must not be empty when specified")
        }
        if config.maxSearchResults < 1 || config.maxSearchResults > 50 {
            errors.append("maxSearchResults must be between 1 and 50")
        }
        for searchType in config.searchTypes where SpotifyItemType.searchable[searchType] == nil {
            errors.append("Invalid search type: '\(searchType)'. Valid: track, album, artist, playlist")
        }
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    func provideActions(query: String, scoring: ScoringContext) async -> [any Action] {
        await buildActions()
    }

    func provideParameterOptions(
        for parameterID: String,
        in _: ActionID,
        query: String
    ) async -> [ParameterOption] {
        guard parameterID == Self.itemParameterID else { return [] }
        return await searchOptions(query)
    }

    private func updateSearchClient() {
        if let clientId = config.clientId,
           !clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            searchClient = SpotifySearchClient(clientId: clientId)
        } else {
            searchClient = nil
        }
    }

    // MARK: - Backend

    /// Where search and Like go: Spotify's own CLI when the installed app has it,
    /// else the Web API when a client ID is configured.
    enum Backend: Sendable {
        case cli(SpotifyCLI)
        case webAPI(SpotifySearchClient)
    }

    var backend: Backend? {
        if let cli = locateCLI() { return .cli(cli) }
        return searchClient.map(Backend.webAPI)
    }

    /// Runs `operation`; if the CLI found Spotify not running, starts it in the
    /// background and runs `operation` again once it's up.
    func whileRunning<T: Sendable>(
        _ cli: SpotifyCLI,
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch SpotifyCLIError.notRunning {
            try await launch(cli)
            return try await operation()
        }
    }

    private func launch(_ cli: SpotifyCLI) async throws {
        if let launching {
            return try await launching.value
        }
        log.info("Spotify isn't running, launching it in the background")
        let task = Task {
            try await SpotifyManager.launchInBackground()
            try await cli.waitUntilReady(timeout: Self.launchTimeout)
        }
        launching = task
        defer { launching = nil }
        try await task.value
    }

    // MARK: - Search

    func searchOptions(_ query: String) async -> [ParameterOption] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= Self.minimumQueryLength, let backend else { return [] }
        searchGeneration += 1
        let generation = searchGeneration
        try? await Task.sleep(for: Self.searchDelay)
        // A newer query came in meanwhile; the picker drops this answer anyway.
        guard generation == searchGeneration else { return [] }

        do {
            return try await search(query, with: backend).map(Self.option(for:))
        } catch {
            log.warning("Search failed: \(error.localizedDescription, privacy: .public)")
            lastSearchError = error.localizedDescription
            return [Self.messageOption(for: error)]
        }
    }

    private func search(_ query: String, with backend: Backend) async throws -> [SpotifySearchItem] {
        let types = config.searchTypes
        let limit = config.maxSearchResults
        switch backend {
        case let .cli(cli):
            return try await whileRunning(cli) {
                try await cli.search(query, types: types, limitPerType: limit)
            }
        case let .webAPI(client):
            return try await client.search(query: query, types: types, limit: limit)
        }
    }

    static func option(for item: SpotifySearchItem) -> ParameterOption {
        ParameterOption(
            id: item.uri,
            label: item.name,
            subtitle: item.subtitle,
            iconName: item.kind.iconName,
            iconURL: item.artworkURL,
            makePreview: { AnyView(SpotifySearchItemPreview(item: item)) }
        )
    }

    private static func messageOption(for error: Error) -> ParameterOption {
        ParameterOption(
            id: messageOptionID,
            label: error.localizedDescription,
            subtitle: error as? SpotifyCLIError == .notRunning ? "Open Spotify and sign in, then search again" : nil,
            iconName: "exclamationmark.triangle"
        )
    }

    // MARK: - Playing

    /// What the search action does with the picked option.
    func playResult(_ optionID: String) async throws -> ActionResult {
        if optionID == Self.messageOptionID {
            return .showResult(title: "Spotify Search", body: lastSearchError ?? "")
        }
        try await play(optionID)
        return .dismiss
    }

    /// Plays through the CLI, starting Spotify first when it isn't running; AppleScript
    /// plays it when the CLI is missing or fails.
    func play(_ uri: String) async throws {
        if let cli = locateCLI() {
            do {
                return try await whileRunning(cli) { try await cli.play(uri) }
            } catch {
                let reason = error.localizedDescription
                log.warning("spotify_cli couldn't play \(uri, privacy: .public): \(reason, privacy: .public)")
            }
        }
        try await SpotifyManager.play(uri)
    }
}

// MARK: - Library

extension SpotifyModule.Backend {
    func isInLibrary(_ uri: String) async throws -> Bool {
        switch self {
        case let .cli(cli): try await cli.isInLibrary(uri)
        case let .webAPI(client): try await client.isInLibrary(uri)
        }
    }

    func addToLibrary(_ uri: String) async throws {
        switch self {
        case let .cli(cli): try await cli.addToLibrary(uri)
        case let .webAPI(client): try await client.addToLibrary(uri)
        }
    }

    func removeFromLibrary(_ uri: String) async throws {
        switch self {
        case let .cli(cli): try await cli.removeFromLibrary(uri)
        case let .webAPI(client): try await client.removeFromLibrary(uri)
        }
    }
}
