import Foundation
import OSLog

struct AliasResult: Sendable {
    let keywordEnrichments: [ActionID: [String]]
    let syntheticActions: [AliasAction]
}

@MainActor
@Observable
final class AliasManager {
    private(set) var aliasEntries: [AliasEntry] = []
    private(set) var aliasErrors: [String] = []

    private let configManager: ConfigManager
    private let eventBus: EventBus

    init(configManager: ConfigManager, eventBus: EventBus) {
        self.configManager = configManager
        self.eventBus = eventBus
    }

    func start() {
        reloadAliases()
        Task { [weak self] in
            guard let self else { return }
            let (_, stream) = await eventBus.subscribe()
            for await event in stream {
                if case .configReloaded = event {
                    self.reloadAliases()
                }
            }
        }
    }

    func findEntry(named aliasName: String) -> AliasEntry? {
        aliasEntries.first { $0.alias == aliasName }
    }

    func buildAction(from entry: AliasEntry) -> AliasAction {
        let targetActionID = ActionID(entry.action)
        let prefilled = entry.parameters ?? [:]
        let hasQueryPlaceholder = prefilled.values.contains { $0.contains("{query}") }
            || entry.action.contains("{query}")

        var parameters: [ActionParameter] = []
        if hasQueryPlaceholder {
            parameters.append(ActionParameter(
                id: "query",
                label: "Query",
                type: .text(placeholder: entry.subtitle ?? "Enter value\u{2026}"),
                isRequired: true
            ))
        }

        let subtitle = entry.subtitle ?? entry.action
        let defaultIcon = Self.defaultIcon(for: entry.action)
        let keywords = (entry.keywords ?? []) + ["alias", entry.alias.lowercased()]

        return AliasAction(
            id: ActionID(module: "alias", name: entry.alias),
            title: entry.alias,
            subtitle: subtitle,
            iconName: entry.icon ?? defaultIcon,
            relevanceScore: 0.9,
            keywords: keywords,
            parameters: parameters,
            targetActionID: targetActionID,
            prefilledParameters: prefilled,
            browser: entry.browser,
            profile: entry.profile
        )
    }

    private static func defaultIcon(for action: String) -> String {
        if action.hasPrefix("http://") || action.hasPrefix("https://") {
            return "link"
        }
        if action.hasPrefix("/") || action.hasPrefix("~/") {
            return "folder"
        }
        return "star.fill"
    }

    func applyAliases(to actions: [any Action]) -> AliasResult {
        var enrichments: [ActionID: [String]] = [:]
        var synthetics: [AliasAction] = []

        let actionIDs = Set(actions.map(\.id))

        for entry in aliasEntries {
            if Self.enriches(entry, actionIDs: actionIDs) {
                let extra = [entry.alias, entry.alias.lowercased()]
                    + (entry.keywords ?? [])
                enrichments[ActionID(entry.action), default: []].append(contentsOf: extra)
            } else {
                synthetics.append(buildAction(from: entry))
            }
        }

        return AliasResult(
            keywordEnrichments: enrichments,
            syntheticActions: synthetics
        )
    }

    /// Whether `entry` only adds its name and keywords to an action that's already listed,
    /// rather than getting a picker entry of its own. That leaves out aliases that open a
    /// URL or folder, or give the action parameters: preset ones, or a `{query}`.
    nonisolated static func enriches(_ entry: AliasEntry, actionIDs: Set<ActionID>) -> Bool {
        let isDirectOpen = entry.action.hasPrefix("http://")
            || entry.action.hasPrefix("https://")
            || entry.action.hasPrefix("/")
            || entry.action.hasPrefix("~/")
        return !isDirectOpen
            && !entry.action.contains("{query}")
            && (entry.parameters ?? [:]).isEmpty
            && actionIDs.contains(ActionID(entry.action))
    }

    // MARK: - Private

    private func reloadAliases() {
        let entries = configManager.config.aliases
        let errors = validate(entries)
        aliasErrors = errors
        if errors.isEmpty {
            aliasEntries = entries
            Log.config.info("Loaded \(entries.count, privacy: .public) aliases")
        } else {
            for error in errors {
                Log.config.error("Alias config error: \(error, privacy: .public)")
            }
            // Still load valid entries even if some have errors
            aliasEntries = entries
        }
    }

    private func validate(_ entries: [AliasEntry]) -> [String] {
        var errors: [String] = []
        var seenAliases = Set<String>()

        for (index, entry) in entries.enumerated() {
            if entry.alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("Alias at index \(index) has an empty alias")
            }
            if entry.action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("Alias '\(entry.alias)' has an empty action")
            }
            if seenAliases.contains(entry.alias) {
                errors.append("Duplicate alias: '\(entry.alias)'")
            }
            seenAliases.insert(entry.alias)
        }

        return errors
    }
}
