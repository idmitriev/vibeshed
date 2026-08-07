import AppKit
import Foundation
import OSLog

actor WebSearchModule: ModuleConfigurable {
    let id = "websearch"
    let displayName = "Web Search"
    let iconName = "magnifyingglass"
    var isEnabled = true

    typealias Config = WebSearchConfig
    static var defaultConfig: Config? {
        .init()
    }

    /// Search actions embed the query text, so the picker re-queries this module
    /// on every keystroke instead of serving it from the corpus cache.
    static let isQueryDependent = true

    private var config: WebSearchConfig = .init()
    private let log = Log.module("websearch")

    func initialize(context: ModuleContext) async throws {
        log.info("WebSearch module initialized")
    }

    func configDidUpdate(_ config: WebSearchConfig) async {
        self.config = config
        log.debug("Config updated")
    }

    static func validate(_ config: WebSearchConfig) -> ConfigValidationResult {
        var errors: [String] = []
        if config.minQueryLength < 1 {
            errors.append("minQueryLength must be at least 1")
        }
        if config.engines.isEmpty {
            errors.append("engines must not be empty")
        }
        for engine in config.engines {
            if engine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("Engine name cannot be empty")
            }
            if !engine.urlTemplate.contains("{query}") {
                errors.append("Engine '\(engine.name)' urlTemplate must contain {query}")
            }
        }
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    func provideActions(query: String, scoring: ScoringContext) async -> [any Action] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= config.minQueryLength else { return [] }

        return config.engines.compactMap { engine in
            buildSearchAction(engine: engine, query: trimmed)
        }
    }

    // MARK: - Action Building

    private func buildSearchAction(
        engine: WebSearchConfig.Engine,
        query: String
    ) -> WebSearchAction? {
        guard let url = Self.searchURL(template: engine.urlTemplate, query: query) else {
            log.warning("Cannot build search URL for engine '\(engine.name, privacy: .public)'")
            return nil
        }
        let slug = engine.name.lowercased().replacingOccurrences(of: " ", with: "-")
        return WebSearchAction(
            id: ActionID(module: "websearch", name: "search.\(slug)"),
            title: "Search \(engine.name) for \u{201C}\(query)\u{201D}",
            subtitle: url.absoluteString,
            iconName: engine.iconName ?? "magnifyingglass",
            keywords: [query.lowercased(), "search", "web", engine.name.lowercased()]
        ) { _ in
            // Opening via NSWorkspace routes through the default browser, so the
            // app's own urlRouting rules apply when Vibeshed is the default handler.
            await MainActor.run {
                NSWorkspace.shared.open(url)
            }
            return .dismiss
        }
    }

    /// Percent-encodes the query and substitutes it into the engine's `{query}` template.
    static func searchURL(template: String, query: String) -> URL? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: queryValueAllowed)
        else { return nil }
        return URL(string: template.replacingOccurrences(of: "{query}", with: encoded))
    }

    /// `.urlQueryAllowed` minus characters that are structural inside a query value.
    private static let queryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&+=?#/")
        return set
    }()
}
