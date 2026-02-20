import AppKit
import Foundation
import OSLog

actor BrowserModule: ModuleConfigurable {
    let id = "browser"
    let displayName = "Browser Tabs"
    let iconName = "globe"
    var isEnabled = true

    typealias Config = BrowserConfig
    static var defaultConfig: Config? { .init() }

    static var requiredPermissions: Set<Permission> { [] }

    private var config: BrowserConfig = .init()
    private let browserManager = BrowserManager()
    private var context: ModuleContext?
    private let log = Log.module("browser")

    // Cache
    private var tabCache: [TabInfo] = []
    private var cacheTimestamp: Date = .distantPast

    func initialize(context: ModuleContext) async throws {
        self.context = context
        log.info("Browser module initialized")
    }

    func configDidUpdate(_ config: BrowserConfig) async {
        self.config = config
        invalidateCache()
        log.debug("Config updated, cache invalidated")
    }

    static func validate(_ config: BrowserConfig) -> ConfigValidationResult {
        var errors: [String] = []
        if config.cacheTTLSeconds < 0 {
            errors.append("cacheTTLSeconds must be non-negative")
        }
        if config.maxResults < 0 {
            errors.append("maxResults must be non-negative")
        }
        for browser in config.browsers {
            let resolved = BrowserRegistry.resolveBundleID(browser)
            // If it resolved to itself and doesn't look like a bundle ID, it's unknown
            if resolved == browser, !browser.contains(".") {
                errors.append("Unknown browser name: '\(browser)'")
            }
        }
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    func provideActions(query: String, scoring: ScoringContext) async -> [any Action] {
        let mgr = browserManager
        let cfg = config

        var actions: [any Action] = buildStaticActions(manager: mgr, config: cfg)

        // Add per-tab top-level actions
        let tabs = await getCachedOrFreshTabs()
        for tab in tabs {
            actions.append(buildTabAction(for: tab, manager: mgr))
        }

        guard !query.isEmpty else { return actions }
        let lowered = query.lowercased()
        return actions.filter { action in
            action.title.lowercased().contains(lowered)
                || action.subtitle.lowercased().contains(lowered)
                || action.keywords.contains { $0.contains(lowered) }
        }
    }

    func provideParameterOptions(
        for parameterID: String,
        in _: ActionID,
        query: String
    ) async -> [ParameterOption] {
        switch parameterID {
        case "tab":
            let tabs = await getCachedOrFreshTabs()
            let options = tabs.map { tab in
                let appURL = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: tab.browserBundleID
                )
                return ParameterOption(
                    id: tab.id,
                    label: tab.displayLabel,
                    subtitle: tab.displaySubtitle,
                    iconName: "globe",
                    iconURL: appURL
                )
            }
            guard !query.isEmpty else { return options }
            let lowered = query.lowercased()
            return options.filter {
                $0.label.lowercased().contains(lowered)
            }

        case "browser":
            let browsers = resolveBrowserList()
            let options = browsers.map { browser in
                let appURL = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: browser.bundleID
                )
                return ParameterOption(
                    id: browser.bundleID,
                    label: browser.name,
                    iconName: "globe",
                    iconURL: appURL
                )
            }
            guard !query.isEmpty else { return options }
            let lowered = query.lowercased()
            return options.filter {
                $0.label.lowercased().contains(lowered)
            }

        default:
            return []
        }
    }

    // MARK: - Cache

    private func getCachedOrFreshTabs() async -> [TabInfo] {
        let now = Date()
        if now.timeIntervalSince(cacheTimestamp) < config.cacheTTLSeconds, !tabCache.isEmpty {
            return tabCache
        }
        let browsers = resolveBrowserList()
        let tabs = await browserManager.listAllTabs(browsers: browsers)
        tabCache = config.maxResults > 0 ? Array(tabs.prefix(config.maxResults)) : tabs
        cacheTimestamp = now
        return tabCache
    }

    private func invalidateCache() {
        tabCache = []
        cacheTimestamp = .distantPast
    }

    // MARK: - Browser Resolution

    private func resolveBrowserList() -> [(name: String, bundleID: String)] {
        if config.browsers.isEmpty {
            return BrowserRegistry.appleScriptCapable.map { ($0.name, $0.bundleID) }
        }
        return config.browsers.map { browser in
            let bundleID = BrowserRegistry.resolveBundleID(browser)
            let name = BrowserRegistry.name(for: bundleID) ?? browser.capitalized
            return (name: name, bundleID: bundleID)
        }
    }

    // MARK: - Static Actions

    private func buildStaticActions(manager mgr: BrowserManager, config cfg: BrowserConfig) -> [BrowserAction] {
        var actions: [BrowserAction] = []
        actions.append(buildFocusTabAction(manager: mgr))
        if cfg.showCloseActions {
            actions.append(buildCloseTabAction(manager: mgr))
        }
        actions.append(buildOpenURLAction(manager: mgr))
        return actions
    }

    private func buildFocusTabAction(manager mgr: BrowserManager) -> BrowserAction {
        BrowserAction(
            id: ActionID(module: "browser", name: "focusTab"),
            title: "Focus Tab",
            subtitle: "Focus a browser tab",
            iconName: "globe",
            relevanceScore: 0.85,
            keywords: ["focus", "tab", "browser", "switch"],
            parameters: [
                ActionParameter(id: "tab", label: "Tab", type: .dynamicSelection(hint: "tab"), isRequired: true),
            ]
        ) { [mgr] values in
            guard let tabID = values["tab"] as? String else {
                return .showResult(title: "Error", body: "No tab selected")
            }
            guard let tab = await Self.resolveTab(id: tabID, manager: mgr) else {
                return .showResult(title: "Tab Not Found", body: "The tab may have been closed or moved.")
            }
            try await mgr.focusTab(tab)
            return .dismiss
        }
    }

    private func buildCloseTabAction(manager mgr: BrowserManager) -> BrowserAction {
        BrowserAction(
            id: ActionID(module: "browser", name: "closeTab"),
            title: "Close Tab",
            subtitle: "Close a browser tab",
            iconName: "xmark.circle",
            relevanceScore: 0.7,
            keywords: ["close", "tab", "browser"],
            parameters: [
                ActionParameter(id: "tab", label: "Tab", type: .dynamicSelection(hint: "tab"), isRequired: true),
            ]
        ) { [mgr] values in
            guard let tabID = values["tab"] as? String else {
                return .showResult(title: "Error", body: "No tab selected")
            }
            guard let tab = await Self.resolveTab(id: tabID, manager: mgr) else {
                return .showResult(title: "Tab Not Found", body: "The tab may have been closed or moved.")
            }
            try await mgr.closeTab(tab)
            return .dismiss
        }
    }

    private func buildOpenURLAction(manager mgr: BrowserManager) -> BrowserAction {
        BrowserAction(
            id: ActionID(module: "browser", name: "openURL"),
            title: "Open URL in Browser",
            subtitle: "Open a URL in a new browser tab",
            iconName: "link",
            relevanceScore: 0.75,
            keywords: ["open", "url", "browser", "new", "tab", "link"],
            parameters: [
                ActionParameter(id: "url", label: "URL", type: .text(placeholder: "https://..."), isRequired: true),
                ActionParameter(
                    id: "browser", label: "Browser",
                    type: .dynamicSelection(hint: "browser"), isRequired: true
                ),
            ]
        ) { [mgr] values in
            guard let urlString = values["url"] as? String, !urlString.isEmpty else {
                return .showResult(title: "Error", body: "No URL provided")
            }
            guard let bundleID = values["browser"] as? String else {
                return .showResult(title: "Error", body: "No browser selected")
            }
            try await mgr.openURL(urlString, in: bundleID)
            return .dismiss
        }
    }

    /// Resolve a composite tab ID back to a live TabInfo by re-querying the browser.
    private static func resolveTab(id tabID: String, manager mgr: BrowserManager) async -> TabInfo? {
        let parts = tabID.split(separator: ":", maxSplits: 2)
        guard parts.count == 3 else { return nil }
        let bundleID = String(parts[0])
        let browserName = BrowserRegistry.name(for: bundleID) ?? "Browser"
        let currentTabs = (try? await mgr.listTabs(for: bundleID, browserName: browserName)) ?? []
        return currentTabs.first(where: { $0.id == tabID })
    }

    // MARK: - Per-Tab Actions

    private func buildTabAction(for tab: TabInfo, manager mgr: BrowserManager) -> BrowserAction {
        BrowserAction(
            id: ActionID(module: "browser", name: "tab.\(tab.id)"),
            title: tab.displayLabel,
            subtitle: tab.displaySubtitle,
            iconName: "globe",
            relevanceScore: 0.65,
            keywords: ["tab", "browser", tab.browserName.lowercased(), tab.domain.lowercased()],
            browserBundleID: tab.browserBundleID,
            tabURL: tab.url
        ) { [mgr] _ in
            do {
                try await mgr.focusTab(tab)
                return .dismiss
            } catch {
                return .showResult(title: "Error", body: error.localizedDescription)
            }
        }
    }
}
