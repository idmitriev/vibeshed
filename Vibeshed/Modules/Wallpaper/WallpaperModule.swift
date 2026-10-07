import AppKit
import Foundation
import OSLog
import SwiftUI

/// Searches wallpaper sites and museum collections (see `WallpaperSourceID`) and sets
/// the picked image as the wallpaper. Search results come in as the parameter's options:
/// thumbnails in the list, a large preview with credits beside it.
actor WallpaperModule: ModuleConfigurable {
    let id = "wallpaper"
    let displayName = "Wallpaper"
    let iconName = "photo.on.rectangle.angled"
    var isEnabled = true

    typealias Config = WallpaperConfig
    static var defaultConfig: Config? {
        .init()
    }

    /// Parameters: `source` (`all` or a source name) for both actions, then the search's
    /// `wallpaper` (a result's option ID) or the random pick's `query` (empty: featured).
    static let sourceParameterID = "source"
    static let wallpaperParameterID = "wallpaper"
    static let queryParameterID = "query"
    static let allSources = "all"
    /// Waited on top of the picker's debounce before a query goes out, so typing a word
    /// costs one search per source rather than one per letter (Unsplash allows 50 an hour).
    static let searchDelay: Duration = .milliseconds(250)
    /// Shorter queries show the featured selection.
    static let minimumQueryLength = 2

    private(set) var config = WallpaperConfig()
    private(set) var sources: [WallpaperSourceID: any WallpaperSource] = [:]
    let log = Log.module("wallpaper")
    private var cache = WallpaperSearchCache()
    /// Wallpapers listed lately by option ID, for the action that runs with one.
    private var listed: [String: OnlineWallpaper] = [:]
    /// Each source's latest search error, for the message row that reports it.
    private var lastErrors: [WallpaperSourceID: String] = [:]
    /// Sources that answered with a browser check, left out of mixed searches for a while.
    private var blockedSince: [WallpaperSourceID: ContinuousClock.Instant] = [:]
    static let blockedSourceBreak: Duration = .seconds(30 * 60)
    private var searchGeneration = 0
    /// Builds each source for a config; tests hand in stubs.
    private let makeSource: @Sendable (WallpaperSourceID, WallpaperConfig) -> any WallpaperSource

    init(
        makeSource: @escaping @Sendable (WallpaperSourceID, WallpaperConfig) -> any WallpaperSource
            = WallpaperModule.makeSource
    ) {
        self.makeSource = makeSource
    }

    func initialize(context _: ModuleContext) async throws {
        rebuildSources()
        log.info("Wallpaper module initialized")
    }

    func configDidUpdate(_ config: WallpaperConfig) async {
        self.config = config
        rebuildSources()
        cache = WallpaperSearchCache()
        let names = config.activeSources.map(\.rawValue).joined(separator: ", ")
        log.debug("Config updated; sources: \(names, privacy: .public)")
    }

    static func validate(_ config: WallpaperConfig) -> ConfigValidationResult {
        let errors = config.validationErrors()
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    func provideActions(query _: String, scoring _: ScoringContext) async -> [any Action] {
        let actions = buildActions()
        guard let enabled = config.enabledActions else { return actions }
        return actions.filter { enabled.contains($0.id.actionName) }
    }

    func provideParameterOptions(
        for parameterID: String,
        in _: ActionID,
        query: String,
        collected: ParameterValues
    ) async -> [ParameterOption] {
        let sourceIDs = Self.sources(for: collected[Self.sourceParameterID], config: config)
        switch parameterID {
        case Self.wallpaperParameterID:
            return await searchOptions(query, sources: sourceIDs)
        case Self.queryParameterID:
            return Self.subjectOptions(query, sources: sourceIDs)
        default:
            return []
        }
    }

    private func rebuildSources() {
        sources = Dictionary(uniqueKeysWithValues: WallpaperSourceID.allCases.map { ($0, makeSource($0, config)) })
    }

    static func makeSource(_ source: WallpaperSourceID, _ config: WallpaperConfig) -> any WallpaperSource {
        switch source {
        case .wallhaven: WallhavenSource(apiKey: config.wallhavenAPIKey, categories: config.wallhavenCategories)
        case .unsplash: UnsplashSource(accessKey: config.unsplashAccessKey)
        case .artic: ArticSource()
        case .rijksmuseum: RijksmuseumSource()
        case .met: MetSource()
        }
    }

    /// The sources a `source` value covers: every active one for `all` (or none given,
    /// as from a URI without it), else that one.
    static func sources(for value: String?, config: WallpaperConfig) -> [WallpaperSourceID] {
        guard let value, value != allSources, let source = WallpaperSourceID(rawValue: value) else {
            return config.activeSources
        }
        return [source]
    }
}

// MARK: - Searching

extension WallpaperModule {
    func searchOptions(_ query: String, sources requested: [WallpaperSourceID]) async -> [ParameterOption] {
        // A source's own search always asks it, so it shows when the block has lifted.
        let sourceIDs = requested.count > 1 ? requested.filter { !isBlocked($0) } : requested
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = trimmed.count < Self.minimumQueryLength ? "" : trimmed
        searchGeneration += 1
        let generation = searchGeneration
        if !query.isEmpty, sourceIDs.contains(where: { cache.results($0, query) == nil }) {
            try? await Task.sleep(for: Self.searchDelay)
            // A newer query came in meanwhile; the picker drops this answer anyway.
            guard generation == searchGeneration else { return [] }
        }

        let outcomes = await search(query, in: sourceIDs)
        var lists: [[OnlineWallpaper]] = []
        var messages: [ParameterOption] = []
        for (source, outcome) in outcomes {
            switch outcome {
            case let .success(results):
                lists.append(results)
            case let .failure(error):
                let reason = error.localizedDescription
                log.warning("\(source.rawValue, privacy: .public) search failed: \(reason, privacy: .public)")
                if case WallpaperSourceError.blocked = error {
                    blockedSince[source] = .now
                    // It would say so in every mixed search; only its own search reports it.
                    if sourceIDs.count > 1 { continue }
                }
                messages.append(messageOption(error, source: source))
            }
        }
        let results = Self.interleaved(lists)
        remember(results)
        return results.map(Self.option) + messages
    }

    func isBlocked(_ source: WallpaperSourceID) -> Bool {
        guard let since = blockedSince[source] else { return false }
        return since.duration(to: .now) < Self.blockedSourceBreak
    }

    /// Each source's results for `query`, from the cache where fresh, in `sourceIDs` order.
    private func search(
        _ query: String,
        in sourceIDs: [WallpaperSourceID]
    ) async -> [(WallpaperSourceID, Result<[OnlineWallpaper], Error>)] {
        let options = config.searchOptions
        var outcomes: [WallpaperSourceID: Result<[OnlineWallpaper], Error>] = [:]
        var pending: [(WallpaperSourceID, any WallpaperSource)] = []
        for sourceID in sourceIDs {
            if let cached = cache.results(sourceID, query) {
                outcomes[sourceID] = .success(cached)
            } else if let source = sources[sourceID] {
                pending.append((sourceID, source))
            }
        }
        await withTaskGroup(of: (WallpaperSourceID, Result<[OnlineWallpaper], Error>).self) { group in
            for (sourceID, source) in pending {
                group.addTask {
                    do {
                        return try await (sourceID, .success(source.search(query, options: options)))
                    } catch {
                        return (sourceID, .failure(error))
                    }
                }
            }
            for await (sourceID, outcome) in group {
                outcomes[sourceID] = outcome
                if case let .success(results) = outcome {
                    cache.store(results, sourceID, query)
                }
            }
        }
        return sourceIDs.compactMap { sourceID in outcomes[sourceID].map { (sourceID, $0) } }
    }

    /// One from each source in turn, so every source shows near the top.
    static func interleaved(_ lists: [[OnlineWallpaper]]) -> [OnlineWallpaper] {
        var seen = Set<String>()
        var result: [OnlineWallpaper] = []
        for index in 0 ..< (lists.map(\.count).max() ?? 0) {
            for list in lists where index < list.count && seen.insert(list[index].id).inserted {
                result.append(list[index])
            }
        }
        return result
    }

    private func remember(_ wallpapers: [OnlineWallpaper]) {
        if listed.count > 1000 { listed.removeAll() }
        for wallpaper in wallpapers {
            listed[wallpaper.id] = wallpaper
        }
    }

    static func option(for wallpaper: OnlineWallpaper) -> ParameterOption {
        ParameterOption(
            id: wallpaper.id,
            label: wallpaper.title,
            subtitle: subtitle(for: wallpaper),
            iconName: wallpaper.source.iconName,
            iconURL: wallpaper.thumbnailURL,
            // Wallhaven's palette; Unsplash's single average color says little.
            swatches: wallpaper.colors.count > 1
                ? wallpaper.colors.prefix(5).compactMap { ThemeColor(hex: $0)?.color }
                : [],
            makePreview: { AnyView(OnlineWallpaperPreview(wallpaper: wallpaper)) }
        )
    }

    /// "The Met · Vincent van Gogh · 1887"; Wallhaven, which has neither, adds its details.
    static func subtitle(for wallpaper: OnlineWallpaper) -> String {
        var parts = [wallpaper.source.shortName] + [wallpaper.credit, wallpaper.date].compactMap(\.self)
        if parts.count == 1, let detail = wallpaper.detail {
            parts.append(detail)
        }
        return parts.joined(separator: " · ")
    }

    private static let messagePrefix = "message:"

    /// A row saying why a source has no results; picking it shows the message.
    private func messageOption(_ error: Error, source: WallpaperSourceID) -> ParameterOption {
        let message = error.localizedDescription
        lastErrors[source] = message
        return ParameterOption(
            id: Self.messagePrefix + source.rawValue,
            label: message,
            subtitle: Self.hint(for: error),
            iconName: "exclamationmark.triangle"
        )
    }

    private static func hint(for error: Error) -> String? {
        switch error as? WallpaperSourceError {
        case .missingKey(.unsplash), .unauthorized(.unsplash):
            "Set unsplashAccessKey under wallpaper: in config.yaml"
        case .unauthorized(.wallhaven):
            "Check wallhavenAPIKey under wallpaper: in config.yaml"
        case .blocked(.artic):
            "Its image server asks for a Cloudflare browser check; remove artic from sources until that ends"
        case .rateLimited:
            "Results come back once the limit resets"
        default:
            nil
        }
    }
}

// MARK: - Setting

extension WallpaperModule {
    /// Sets the wallpaper picked in a search (or named by an alias or URI).
    func setWallpaper(optionID: String) async throws -> ActionResult {
        if optionID.hasPrefix(Self.messagePrefix) {
            let source = WallpaperSourceID(rawValue: String(optionID.dropFirst(Self.messagePrefix.count)))
            return .showResult(title: source?.displayName ?? "Wallpaper", body: source.flatMap { lastErrors[$0] } ?? "")
        }
        guard let wallpaper = try await wallpaper(optionID: optionID) else {
            return .showResult(title: "Wallpaper", body: "Couldn't find \(optionID)")
        }
        return try await apply(wallpaper)
    }

    func wallpaper(optionID: String) async throws -> OnlineWallpaper? {
        if let wallpaper = listed[optionID] { return wallpaper }
        guard let (sourceID, itemID) = OnlineWallpaper.parseOptionID(optionID), let source = sources[sourceID] else {
            return nil
        }
        return try await source.wallpaper(itemID: itemID)
    }

    /// A random image for the action's `source` (`all` or a name) and `query` values.
    func setRandomWallpaper(source: String?, query: String?) async throws -> ActionResult {
        try await setRandomWallpaper(from: Self.sources(for: source, config: config), query: query)
    }

    /// A random image from one of `sourceIDs`, trying the others when one fails or has
    /// nothing: from its featured images, or from its search results for `query`.
    func setRandomWallpaper(from requested: [WallpaperSourceID], query: String? = nil) async throws -> ActionResult {
        let query = Self.subject(query)
        let sourceIDs = requested.count > 1 ? requested.filter { !isBlocked($0) } : requested
        var lastError: Error?
        for sourceID in sourceIDs.shuffled() {
            guard let source = sources[sourceID] else { continue }
            do {
                if let wallpaper = try await randomPick(from: source, query: query) {
                    return try await apply(wallpaper)
                }
            } catch {
                let reason = error.localizedDescription
                log.warning("Random from \(sourceID.rawValue, privacy: .public) failed: \(reason, privacy: .public)")
                lastError = error
            }
        }
        if let lastError { throw lastError }
        let body = query.isEmpty ? "None of the sources had one to offer" : "Nothing found for “\(query)”"
        return .showResult(title: "Random Wallpaper", body: body)
    }

    private func randomPick(from source: any WallpaperSource, query: String) async throws -> OnlineWallpaper? {
        let options = config.searchOptions
        guard !query.isEmpty else { return try await source.random(options: options) }
        let results: [OnlineWallpaper]
        if let cached = cache.results(source.id, query) {
            results = cached
        } else {
            results = try await source.search(query, options: options)
            cache.store(results, source.id, query)
        }
        return results.filter { options.orientation.matches($0.aspectRatio) }.randomElement() ?? results.randomElement()
    }

    /// The `query` option that stands for "anything": the featured images.
    static let featuredSubject = "*"

    /// A random pick's subject, empty for the featured images.
    static func subject(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed == featuredSubject ? "" : trimmed
    }

    /// The random pick's subject step: what's typed, or "Anything" when nothing is.
    static func subjectOptions(_ query: String, sources: [WallpaperSourceID]) -> [ParameterOption] {
        let subject = subject(query)
        let owner = sources.count == 1 ? "\(sources[0].displayName)’s " : ""
        guard !subject.isEmpty else {
            return [ParameterOption(
                id: featuredSubject, label: "Anything", subtitle: "A random pick from \(owner)featured images",
                iconName: "shuffle"
            )]
        }
        return [ParameterOption(
            id: subject, label: "“\(subject)”", subtitle: "A random pick from \(owner)results for it",
            iconName: "magnifyingglass"
        )]
    }

    /// Downloads `wallpaper` and puts it on every screen.
    func apply(_ wallpaper: OnlineWallpaper) async throws -> ActionResult {
        let longestSide = await MainActor.run { DesktopPicture.longestScreenSide() }
        let file = try await WallpaperDownloads.file(
            for: wallpaper, longestSide: longestSide, in: WallpaperDownloads.directory(for: config)
        )
        let source = wallpaper.source
        let scaling = config.resolvedScaling
        let image = WallpaperPlacement.Image(file, source: source, scaling: scaling)
        let placements = try await MainActor.run {
            try DesktopPicture.set(file) { aspectRatio in
                WallpaperPlacement.choose(for: image, source: source, scaling: scaling, screenAspectRatio: aspectRatio)
            }
        }
        let placed = placements.map(String.init(describing:)).joined(separator: ", ")
        let name = "\(wallpaper.id) (\(file.lastPathComponent))"
        log.info("Set wallpaper \(name, privacy: .public): \(placed, privacy: .public)")
        if config.downloadDirectory == nil {
            await WallpaperDownloads.prune()
        }
        if let unsplash = sources[.unsplash] as? UnsplashSource, wallpaper.source == .unsplash {
            do {
                try await unsplash.trackDownload(wallpaper)
            } catch {
                log.warning("Unsplash download tracking failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return .showResult(title: "Wallpaper Set", body: Self.creditLine(wallpaper))
    }

    /// "A Ship on the High Seas — Willem van de Velde (II), c. 1680 · Rijksmuseum"
    static func creditLine(_ wallpaper: OnlineWallpaper) -> String {
        let maker = [wallpaper.credit, wallpaper.date].compactMap(\.self).joined(separator: ", ")
        let work = maker.isEmpty ? wallpaper.title : "\(wallpaper.title) — \(maker)"
        return "\(work) · \(wallpaper.source.displayName)"
    }

    /// Opens the web page the current wallpaper was downloaded from.
    func openSourcePage() async -> ActionResult {
        guard let file = await MainActor.run(body: { DesktopPicture.current }) else {
            return .showResult(title: "Wallpaper", body: "Couldn't find the current wallpaper")
        }
        guard let page = WallpaperDownloads.sourcePage(of: file) else {
            let body = "\(file.lastPathComponent) doesn't record where it came from"
            return .showResult(title: "No Source Page", body: body)
        }
        await MainActor.run { _ = NSWorkspace.shared.open(page) }
        return .dismiss
    }
}

/// Recent results per source and query, so refining or backspacing doesn't search again.
struct WallpaperSearchCache {
    static let lifetime: Duration = .seconds(10 * 60)
    private static let limit = 200
    private var entries: [String: (results: [OnlineWallpaper], fetchedAt: ContinuousClock.Instant)] = [:]

    func results(_ source: WallpaperSourceID, _ query: String) -> [OnlineWallpaper]? {
        guard let entry = entries[Self.key(source, query)], entry.fetchedAt.duration(to: .now) < Self.lifetime
        else { return nil }
        return entry.results
    }

    mutating func store(_ results: [OnlineWallpaper], _ source: WallpaperSourceID, _ query: String) {
        if entries.count >= Self.limit { entries.removeAll() }
        entries[Self.key(source, query)] = (results, .now)
    }

    private static func key(_ source: WallpaperSourceID, _ query: String) -> String {
        "\(source.rawValue)\u{1}\(query.lowercased())"
    }
}
