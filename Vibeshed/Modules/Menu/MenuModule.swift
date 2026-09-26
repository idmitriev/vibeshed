import Foundation
import OSLog

/// The menu bar of the app the user is in, as actions: `menu/search` lists its items,
/// and (with `showInSearch`) every item is also an action in the main search.
///
/// Item IDs are the menu path itself (`menu/File > New Tab`) and are pressed in
/// whichever app owns the menu bar when they run, so they also work from
/// keybindings, aliases, and vibeshed:// URIs.
actor MenuModule: ModuleConfigurable {
    let id = "menu"
    let displayName = "Menu Items"
    let iconName = "filemenu.and.selection"
    var isEnabled = true

    typealias Config = MenuConfig
    static var defaultConfig: Config? {
        .init()
    }

    static var requiredPermissions: Set<Permission> {
        [.accessibility]
    }

    private static let searchActionName = "search"
    private static let itemParameterID = "item"
    private static let itemIcon = "filemenu.and.selection"

    private struct Snapshot {
        let pid: pid_t
        let entries: [MenuItemEntry]
    }

    private var config = MenuConfig()
    private var cache = TimedCache<Snapshot>(ttl: MenuConfig().cacheTTLSeconds)
    /// In-flight crawls, so the catalog fetch and a parameter-options fetch that
    /// overlap share one pass over the menus.
    private var crawls: [pid_t: Task<[MenuItemEntry], Never>] = [:]
    private let log = Log.module("menu")

    func initialize(context: ModuleContext) async throws {
        log.info("Menu module initialized")
    }

    func configDidUpdate(_ config: MenuConfig) async {
        self.config = config
        cache = TimedCache(ttl: config.cacheTTLSeconds)
        log.debug("Config updated, cache invalidated")
    }

    static func validate(_ config: MenuConfig) -> ConfigValidationResult {
        var errors: [String] = []
        if config.maxSubmenuItems < 1 {
            errors.append("maxSubmenuItems must be at least 1")
        }
        if config.cacheTTLSeconds < 0 {
            errors.append("cacheTTLSeconds must not be negative")
        }
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    func provideActions(query: String, scoring: ScoringContext) async -> [any Action] {
        let target = await MainActor.run { MenuTarget.current() }
        var actions: [any Action] = [Self.searchAction(target: target)]
        guard config.showInSearch, let target, isListable(target) else { return actions }
        let entries = await entries(for: target)
        actions += entries.map { Self.itemAction(for: $0, listedFrom: target) }
        return actions
    }

    /// Resolves IDs without reading any menus: a path ID is valid whatever app is in
    /// front now, and the item is looked up when the action runs.
    func action(id: ActionID) async -> (any Action)? {
        guard id.moduleID == self.id else { return nil }
        if id.actionName == Self.searchActionName {
            return await Self.searchAction(target: MainActor.run { MenuTarget.current() })
        }
        guard let path = MenuPath.parse(id.actionName) else { return nil }
        let entry = MenuItemEntry(path: path, shortcut: nil, isChecked: false)
        return Self.itemAction(for: entry, listedFrom: nil)
    }

    func provideParameterOptions(
        for parameterID: String,
        in _: ActionID,
        query _: String
    ) async -> [ParameterOption] {
        guard parameterID == Self.itemParameterID,
              let target = await MainActor.run(body: { MenuTarget.current() }),
              isListable(target)
        else {
            return []
        }
        return await entries(for: target).map { entry in
            ParameterOption(
                id: entry.key,
                label: entry.title,
                subtitle: entry.subtitle,
                iconName: entry.isChecked ? "checkmark" : Self.itemIcon
            )
        }
    }

    // MARK: - Menu snapshot

    private func isListable(_ target: MenuTarget) -> Bool {
        guard let bundleID = target.bundleID else { return true }
        return !config.excludedBundleIDs.contains(bundleID)
    }

    private func entries(for target: MenuTarget) async -> [MenuItemEntry] {
        if let snapshot = cache.value, snapshot.pid == target.pid {
            return snapshot.entries
        }
        if let crawl = crawls[target.pid] {
            return await crawl.value
        }
        let maxSubmenuItems = config.maxSubmenuItems
        let crawl = Task {
            await MenuBarReader.entries(pid: target.pid, maxSubmenuItems: maxSubmenuItems)
        }
        crawls[target.pid] = crawl
        let entries = await crawl.value
        crawls[target.pid] = nil
        cache.store(Snapshot(pid: target.pid, entries: entries))
        return entries
    }
}

// MARK: - Actions

extension MenuModule {
    static func searchAction(target: MenuTarget?) -> MenuAction {
        let owner = target.map { "\($0.name)'s" } ?? "the frontmost app's"
        return MenuAction(
            id: ActionID(module: "menu", name: searchActionName),
            title: "Search Menu Items",
            subtitle: "Find and click an item in \(owner) menus",
            iconName: itemIcon,
            appIconPath: target?.bundleURL?.path,
            relevanceScore: 0.8,
            keywords: ["menu", "menu bar", "menubar", "command", "click"],
            parameters: [
                ActionParameter(
                    id: itemParameterID,
                    label: target?.name ?? "Menu Item",
                    type: .dynamicSelection(hint: itemParameterID),
                    isRequired: true
                ),
            ],
            appName: target?.name
        ) { values in
            guard let key = values[itemParameterID], let path = MenuPath.parse(key) else {
                return .showResult(title: "Error", body: "No menu item selected")
            }
            return await press(path)
        }
    }

    static func itemAction(for entry: MenuItemEntry, listedFrom target: MenuTarget?) -> MenuAction {
        let path = entry.path
        return MenuAction(
            id: ActionID(module: "menu", name: entry.key),
            title: entry.title,
            subtitle: entry.subtitle,
            iconName: entry.isChecked ? "checkmark" : itemIcon,
            appIconPath: target?.bundleURL?.path,
            // Below apps and commands: an app's menu can hold hundreds of items.
            relevanceScore: 0.4,
            keywords: keywords(for: entry.title),
            entry: entry,
            appName: target?.name
        ) { _ in
            await press(path)
        }
    }

    /// The title and each of its words, so typing the start of either earns the
    /// keyword bonus (as Settings does for pane titles). Without it an exact title
    /// match ranks below the web-search fallbacks, whose keywords hold the query.
    static func keywords(for title: String) -> [String] {
        let lowered = title.lowercased()
        let words = lowered.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return [lowered] + words
    }

    /// Presses `path` in the app that owns the menu bar now. From the picker that's
    /// the app the item was listed from; from a keybinding, whatever app is in front.
    private static func press(_ path: [String]) async -> ActionResult {
        guard let target = await MainActor.run(body: { MenuTarget.current() }) else {
            return .showResult(title: "No Menu Bar", body: "No app menu bar to use")
        }
        let item = MenuPath.display(path)
        switch await MenuBarReader.press(path: path, pid: target.pid) {
        case .pressed:
            return .dismiss
        case .notFound:
            return .showResult(title: "Menu Item Not Found", body: "\(target.name) has no '\(item)' menu item")
        case .disabled:
            return .showResult(title: "Menu Item Disabled", body: "'\(item)' is disabled in \(target.name) right now")
        case let .failed(error):
            return .showResult(
                title: "Menu Item Failed",
                body: "Couldn't click '\(item)' in \(target.name) (AXError \(error.rawValue))"
            )
        }
    }
}
