import Foundation
import OSLog

actor FavouritesModule: ModuleConfigurable {
    let id = "favourites"
    let displayName = "Favourites"
    let iconName = "star"
    var isEnabled = true

    typealias Config = FavouritesConfig
    static var defaultConfig: Config? { .init() }

    private var config: FavouritesConfig = .init()
    private var context: ModuleContext?
    private let log = Log.module("favourites")

    func initialize(context: ModuleContext) async throws {
        self.context = context
        log.info("Favourites module initialized (\(self.config.favourites.count, privacy: .public) favourites)")
    }

    func configDidUpdate(_ config: FavouritesConfig) async {
        self.config = config
        log.debug("Config updated (\(config.favourites.count, privacy: .public) favourites)")
    }

    static func validate(_ config: FavouritesConfig) -> ConfigValidationResult {
        var errors: [String] = []

        var seenAliases = Set<String>()
        for (index, entry) in config.favourites.enumerated() {
            if entry.alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("Favourite at index \(index) has an empty alias")
            }
            if entry.action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("Favourite '\(entry.alias)' has an empty action")
            }
            if seenAliases.contains(entry.alias) {
                errors.append("Duplicate favourite alias: '\(entry.alias)'")
            }
            seenAliases.insert(entry.alias)
        }

        return errors.isEmpty ? .valid : .invalid(errors)
    }

    func provideActions(query: String, scoring: ScoringContext) async -> [any Action] {
        let actions = config.favourites.map(buildAction)

        guard !query.isEmpty else { return actions }
        let lowered = query.lowercased()
        return actions.filter { action in
            action.title.lowercased().contains(lowered)
                || action.subtitle.lowercased().contains(lowered)
                || action.keywords.contains { $0.contains(lowered) }
        }
    }

    // MARK: - Build Actions

    private func buildAction(from entry: FavouriteEntry) -> FavouritesAction {
        let targetActionID = ActionID(entry.action)
        let prefilled = entry.parameters ?? [:]
        let hasQueryPlaceholder = prefilled.values.contains { $0.contains("{query}") }

        var parameters: [ActionParameter] = []
        if hasQueryPlaceholder {
            parameters.append(ActionParameter(
                id: "query",
                label: "Query",
                type: .text(placeholder: entry.subtitle ?? "Enter value…"),
                isRequired: true
            ))
        }

        let subtitle = entry.subtitle ?? entry.action
        let keywords = (entry.keywords ?? []) + ["favourite", "fav", entry.alias.lowercased()]

        return FavouritesAction(
            id: ActionID(module: "favourites", name: entry.alias),
            title: entry.alias,
            subtitle: subtitle,
            iconName: entry.icon ?? "star.fill",
            relevanceScore: 0.9,
            keywords: keywords,
            parameters: parameters,
            targetActionID: targetActionID,
            prefilledParameters: prefilled
        )
    }
}
