import Foundation

/// Config knobs every AI vendor module shares. Vendor configs add their own fields
/// (CLI paths, terminal choice) on top; the generic module only reads these.
protocol AIProviderConfig: Codable, Sendable, Equatable {
    /// Maximum number of recent sessions to surface (1–100).
    var maxResults: Int { get }
    /// Whether to expose quick-launch actions alongside session history.
    var showLaunchers: Bool { get }
    /// Action-name suffixes to expose (nil = all).
    var enabledActions: Set<String>? { get }
    /// Which of the vendor's surfaces to scan, by `AISessionSource.id`.
    var sources: [String] { get }
}

/// Describes one AI vendor for `AISessionsModule`. A provider knows how to discover
/// that vendor's sessions and how to reopen one; the generic module owns caching,
/// scoring, search, `enabledActions` filtering and the `Module` plumbing.
///
/// Mirrors the `RecentProjectsProvider` split used by the editor modules.
protocol AIProvider: Sendable {
    associatedtype Config: AIProviderConfig

    static var moduleID: String { get }
    static var displayName: String { get }
    static var iconName: String { get }
    static var cacheTTL: TimeInterval { get }
    static var defaultConfig: Config { get }

    /// Every surface this vendor can read, used to validate config `sources:` entries.
    static var allSources: [AISessionSource] { get }

    static func validate(_ config: Config) -> ConfigValidationResult

    init()

    /// Discovers recent sessions across the configured sources, newest first,
    /// capped at `limit`. Search passes a larger limit than the picker list so
    /// sessions past `maxResults` stay reachable by name.
    func readSessions(config: Config, limit: Int) -> [AISession]

    /// Reopens a session on its own surface (terminal resume, app deeplink, …).
    func openSession(_ session: AISession, config: Config)

    /// Extra per-session actions offered in the picker's action menu, e.g. handing a
    /// CLI session to the desktop app. Default: none.
    func alternateActions(for session: AISession, config: Config) -> [AIAction]

    /// Quick-launch actions (new chat, continue last, open settings…).
    func launcherActions(config: Config) -> [AIAction]
}

extension AIProvider {
    static var cacheTTL: TimeInterval {
        5
    }

    /// This vendor's module identity, for building action ids and preview badges.
    static var identity: AIModuleIdentity {
        AIModuleIdentity(id: moduleID, displayName: displayName)
    }

    /// Validates the shared knobs. Vendor providers that override this should call
    /// `validateCommon` first and append their own errors.
    static func validate(_ config: Config) -> ConfigValidationResult {
        validateCommon(config)
    }

    /// Checks `maxResults` bounds and that every `sources:` entry names a real surface.
    static func validateCommon(_ config: Config) -> ConfigValidationResult {
        var errors: [String] = []
        if config.maxResults < 1 || config.maxResults > 100 {
            errors.append("maxResults must be between 1 and 100")
        }
        let valid = Set(allSources.map(\.id))
        for source in config.sources where !valid.contains(source) {
            errors.append(
                "Invalid source: '\(source)'. Valid: \(valid.sorted().joined(separator: ", "))"
            )
        }
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    func alternateActions(for _: AISession, config _: Config) -> [AIAction] {
        []
    }
}
