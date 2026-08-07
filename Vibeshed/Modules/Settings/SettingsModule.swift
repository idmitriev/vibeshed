import Foundation
import OSLog

actor SettingsModule: ModuleConfigurable {
    let id = "settings"
    let displayName = "System Settings"
    let iconName = "gearshape.2"
    var isEnabled = true

    typealias Config = SettingsConfig
    static var defaultConfig: Config? {
        .init()
    }

    private var config: SettingsConfig = .init()
    private let log = Log.module("settings")

    func initialize(context: ModuleContext) async throws {
        log.info("Settings module initialized")
    }

    func configDidUpdate(_ config: SettingsConfig) async {
        self.config = config
        log.debug("Config updated")
    }

    func provideActions(query: String, scoring: ScoringContext) async -> [any Action] {
        buildActions(config: config)
    }

    // MARK: - Build Actions

    private func buildActions(config: SettingsConfig) -> [SettingsAction] {
        var panes = SettingsPane.catalog
        if let enabled = config.enabledPanes {
            panes = panes.filter { enabled.contains($0.id) }
        }
        if let custom = config.customPanes {
            panes.append(contentsOf: custom.map { title, target in
                SettingsPane(id: target, title: title, iconName: "gearshape.2", target: target, keywords: [])
            })
        }

        return panes.map { pane in
            SettingsAction(
                id: ActionID(module: "settings", name: pane.id),
                title: pane.title,
                subtitle: "Open \(pane.title) settings",
                iconName: pane.iconName,
                relevanceScore: 0.6,
                keywords: ["settings", "preferences", "system"] + titleWords(pane.title) + pane.keywords
            ) { _ in
                SettingsManager.open(pane)
                return .dismiss
            }
        }
    }

    private func titleWords(_ title: String) -> [String] {
        title.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }
}
