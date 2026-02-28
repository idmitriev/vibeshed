import AppKit
import Foundation
import OSLog

actor BookmarkModule: ModuleConfigurable {
    let id = "bookmark"
    let displayName = "Bookmarks & History"
    let iconName = "bookmark"
    var isEnabled = true

    typealias Config = BookmarkConfig
    static var defaultConfig: Config? { .init() }

    static var requiredPermissions: Set<Permission> { [.fullDiskAccess] }

    private var config: BookmarkConfig = .init()
    private var context: ModuleContext?
    private let log = Log.module("bookmark")

    // Cache
    private var bookmarkCache: [BookmarkInfo] = []
    private var visitedCache: [VisitedSite] = []
    private var cacheTimestamp: Date = .distantPast

    func initialize(context: ModuleContext) async throws {
        self.context = context
        log.info("Bookmark module initialized")
    }

    func teardown() async {
        bookmarkCache = []
        visitedCache = []
    }

    func configDidUpdate(_ config: BookmarkConfig) async {
        self.config = config
        invalidateCache()
        log.debug("Config updated, cache invalidated")
    }

    static func validate(_ config: BookmarkConfig) -> ConfigValidationResult {
        var errors: [String] = []
        if config.maxBookmarks < 0 {
            errors.append("maxBookmarks must be non-negative")
        }
        if config.maxVisited < 0 {
            errors.append("maxVisited must be non-negative")
        }
        if config.minVisitCount < 1 {
            errors.append("minVisitCount must be at least 1")
        }
        if config.cacheTTLSeconds < 0 {
            errors.append("cacheTTLSeconds must be non-negative")
        }
        for browser in config.browsers {
            let resolved = BrowserRegistry.resolveBundleID(browser)
            if resolved == browser, !browser.contains(".") {
                errors.append("Unknown browser name: '\(browser)'")
            }
        }
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    func provideActions(query: String, scoring: ScoringContext) async -> [any Action] {
        let (bookmarks, visited) = getCachedOrFreshData()
        let cfg = config

        var actions: [any Action] = []

        // Bookmark actions
        let bookmarkLimit = cfg.maxBookmarks > 0 ? cfg.maxBookmarks : bookmarks.count
        for bookmark in bookmarks.prefix(bookmarkLimit) {
            actions.append(buildBookmarkAction(for: bookmark))
        }

        // Most visited actions
        if cfg.showMostVisited {
            let visitedLimit = cfg.maxVisited > 0 ? cfg.maxVisited : visited.count
            for site in visited.prefix(visitedLimit) {
                actions.append(buildVisitedAction(for: site))
            }
        }

        return actions
    }

    func provideParameterOptions(
        for _: String,
        in _: ActionID,
        query _: String
    ) async -> [ParameterOption] {
        []
    }

    // MARK: - Cache

    private func getCachedOrFreshData() -> ([BookmarkInfo], [VisitedSite]) {
        let now = Date()
        if now.timeIntervalSince(cacheTimestamp) < config.cacheTTLSeconds,
           !bookmarkCache.isEmpty || !visitedCache.isEmpty
        {
            return (bookmarkCache, visitedCache)
        }

        let browsers = resolveBrowserList()
        let bookmarks = BookmarkManager.readBookmarks(browsers: browsers)
        let visited = BookmarkManager.readMostVisited(
            browsers: browsers,
            minVisitCount: config.minVisitCount
        )

        bookmarkCache = bookmarks
        visitedCache = visited
        cacheTimestamp = now

        log.debug("Loaded \(bookmarks.count) bookmarks and \(visited.count) visited sites")
        return (bookmarks, visited)
    }

    private func invalidateCache() {
        bookmarkCache = []
        visitedCache = []
        cacheTimestamp = .distantPast
    }

    // MARK: - Browser Resolution

    private func resolveBrowserList() -> [(name: String, bundleID: String)] {
        if config.browsers.isEmpty {
            return BrowserRegistry.all
                .filter { BrowserRegistry.isInstalled($0.bundleID) }
                .filter { $0.bundleID == "com.apple.Safari" || $0.isChromium }
                .map { ($0.name, $0.bundleID) }
        }
        return config.browsers.map { browser in
            let bundleID = BrowserRegistry.resolveBundleID(browser)
            let name = BrowserRegistry.name(for: bundleID) ?? browser.capitalized
            return (name: name, bundleID: bundleID)
        }
    }

    // MARK: - Action Builders

    private func buildBookmarkAction(for bookmark: BookmarkInfo) -> BookmarkAction {
        let urlHash = bookmark.url.hashValue & 0x7FFFFFFF
        return BookmarkAction(
            id: ActionID(module: "bookmark", name: "bm.\(urlHash)"),
            title: bookmark.title,
            subtitle: bookmark.domain,
            iconName: "bookmark",
            relevanceScore: 0.55,
            keywords: buildBookmarkKeywords(bookmark),
            browserBundleID: bookmark.browserBundleID,
            url: bookmark.url,
            folderPath: bookmark.folderPath
        ) { _ in
            if let url = URL(string: bookmark.url) {
                try BrowserRegistry.open(url: url, browser: bookmark.browserBundleID, profile: nil)
            }
            return .dismiss
        }
    }

    private func buildVisitedAction(for site: VisitedSite) -> BookmarkAction {
        let urlHash = site.url.hashValue & 0x7FFFFFFF
        return BookmarkAction(
            id: ActionID(module: "bookmark", name: "visited.\(urlHash)"),
            title: site.title,
            subtitle: "\(site.domain) — \(site.visitCount) visits",
            iconName: "clock.arrow.circlepath",
            relevanceScore: visitedRelevance(site),
            keywords: buildVisitedKeywords(site),
            browserBundleID: site.browserBundleID,
            url: site.url,
            visitCount: site.visitCount
        ) { _ in
            if let url = URL(string: site.url) {
                try BrowserRegistry.open(url: url, browser: site.browserBundleID, profile: nil)
            }
            return .dismiss
        }
    }

    private func visitedRelevance(_ site: VisitedSite) -> Double {
        // Scale from 0.4 to 0.65 based on visit count (log scale)
        let logCount = log2(Double(max(site.visitCount, 1)))
        let maxLog = log2(500.0)
        return 0.4 + min(0.25, 0.25 * logCount / maxLog)
    }

    private func buildBookmarkKeywords(_ bookmark: BookmarkInfo) -> [String] {
        var kw = ["bookmark", bookmark.browserName.lowercased(), bookmark.domain.lowercased()]
        let folderWords = bookmark.folderPath.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        kw.append(contentsOf: folderWords)
        return kw
    }

    private func buildVisitedKeywords(_ site: VisitedSite) -> [String] {
        ["visited", "history", "frequent", site.browserName.lowercased(), site.domain.lowercased()]
    }
}
