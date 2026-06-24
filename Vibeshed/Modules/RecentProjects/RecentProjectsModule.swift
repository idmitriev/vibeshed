import Foundation
import OSLog

/// Generic module for editor/IDE families that surface recent projects. Specialized
/// per editor by a `RecentProjectsProvider` (VS Code, Zed, JetBrains). Replaces three
/// near-identical `*Module` actors.
actor RecentProjectsModule<Provider: RecentProjectsProvider>: ModuleConfigurable {
    typealias Config = Provider.Config

    let id: String
    let displayName: String
    let iconName: String
    var isEnabled = true

    static var defaultConfig: Config? {
        Provider.defaultConfig
    }

    static func validate(_ config: Config) -> ConfigValidationResult {
        Provider.validate(config)
    }

    private let provider: Provider
    private var config: Config
    private var context: ModuleContext?
    private var cache: TimedCache<[RecentProjectItem]>
    private let log: Logger

    init() {
        provider = Provider()
        id = Provider.moduleID
        displayName = Provider.displayName
        iconName = Provider.iconName
        config = Provider.defaultConfig
        cache = TimedCache(ttl: Provider.cacheTTL)
        log = Log.module(Provider.moduleID)
    }

    func initialize(context: ModuleContext) async throws {
        self.context = context
        refreshCache()
        provider.applySideEffects(config: config)
        log
            .info(
                "\(self.displayName, privacy: .public) module initialized (\(self.cache.value?.count ?? 0, privacy: .public) items found)"
            )
    }

    func teardown() async {
        cache.invalidate()
    }

    func configDidUpdate(_ config: Config) async {
        self.config = config
        refreshCache()
        provider.applySideEffects(config: config)
        log.debug("Config updated, cache refreshed (\(self.cache.value?.count ?? 0, privacy: .public) items)")
    }

    func provideActions(
        query _: String,
        scoring _: ScoringContext
    ) async -> [any Action] {
        buildActions(currentItems())
    }

    // MARK: - Private

    private func currentItems() -> [RecentProjectItem] {
        if let cached = cache.value { return cached }
        refreshCache()
        return cache.value ?? []
    }

    private func refreshCache() {
        cache.store(provider.makeItems(config: config))
    }

    private func buildActions(_ items: [RecentProjectItem]) -> [any Action] {
        var actions = items.enumerated().map { index, item in
            RecentProjectAction(
                id: ActionID(module: id, name: "project.\(StableID.hash(item.stableInput))"),
                relevanceScore: rankedScore(index: index),
                item: item
            )
        }
        if let enabled = provider.enabledActions(config) {
            actions = actions.filter { enabled.contains($0.id.actionName) }
        }
        return actions
    }
}
