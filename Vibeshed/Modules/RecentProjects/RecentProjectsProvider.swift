import Foundation

/// Describes one editor/IDE family for `RecentProjectsModule`. A provider knows how
/// to discover recent projects and turn each into a display-ready `RecentProjectItem`;
/// the generic module owns caching, scoring, `enabledActions` filtering, and the
/// `Module`/`ModuleConfigurable` plumbing.
protocol RecentProjectsProvider: Sendable {
    associatedtype Config: Codable & Sendable & Equatable

    static var moduleID: String { get }
    static var displayName: String { get }
    static var iconName: String { get }
    static var cacheTTL: TimeInterval { get }
    static var defaultConfig: Config { get }
    static func validate(_ config: Config) -> ConfigValidationResult

    init()

    /// Discovers recent projects and renders each as a display-ready item.
    func makeItems(config: Config) -> [RecentProjectItem]

    /// Action-name suffixes to expose (nil = all).
    func enabledActions(_ config: Config) -> Set<String>?

    /// Optional side effects applied on initialize and config change
    /// (e.g. JetBrains "open in new window" patching). Default: no-op.
    func applySideEffects(config: Config)
}

extension RecentProjectsProvider {
    static var cacheTTL: TimeInterval { 5 }
    static func validate(_: Config) -> ConfigValidationResult { .valid }
    func enabledActions(_: Config) -> Set<String>? { nil }
    func applySideEffects(config _: Config) {}
}
