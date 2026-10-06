import Foundation
import OSLog

/// Terminal.app through AppleScript: a new window, Run Command, and configured commands,
/// each in a new window. Theming is the theme module's `terminal` target.
///
/// The config written on first launch turns it on when Homebrew is missing, for the
/// "Install Homebrew" alias (see `DefaultConfig`).
actor TerminalModule: ModuleConfigurable {
    let id = "terminal"
    let displayName = "Terminal"
    let iconName = "terminal"
    var isEnabled = true

    typealias Config = TerminalConfig
    static var defaultConfig: Config? {
        .init()
    }

    var automationTargets: [String] {
        [TerminalManager.bundleID]
    }

    private var config = TerminalConfig()
    private let log = Log.module("terminal")

    func initialize(context _: ModuleContext) async throws {
        log.info("Terminal module initialized")
    }

    func configDidUpdate(_ config: TerminalConfig) async {
        self.config = config
    }

    static func validate(_: TerminalConfig) -> ConfigValidationResult {
        .valid
    }

    func provideActions(query _: String, scoring _: ScoringContext) async -> [any Action] {
        Self.enabled(Self.actions(config: config, appIcon: TerminalManager.appURL?.path), config: config)
    }

    /// `enabledActions` takes full names (`runCommand`) or the `cmd` family.
    static func enabled(_ actions: [TerminalAction], config: TerminalConfig) -> [TerminalAction] {
        guard let enabled = config.enabledActions else { return actions }
        return actions.filter { action in
            let name = action.id.actionName
            return enabled.contains(name) || enabled.contains(String(name.prefix { $0 != "." }))
        }
    }
}

// MARK: - Actions

extension TerminalModule {
    static func actions(config: TerminalConfig, appIcon: String?) -> [TerminalAction] {
        [
            newWindowAction(appIcon: appIcon),
            runCommandAction(appIcon: appIcon),
        ] + commandActions(config.commands, appIcon: appIcon)
    }

    private static func newWindowAction(appIcon: String?) -> TerminalAction {
        TerminalAction(
            id: ActionID(module: "terminal", name: "newWindow"),
            title: "New Window",
            subtitle: "Open a new Terminal window",
            iconName: "macwindow.badge.plus",
            appIconPath: appIcon,
            relevanceScore: 0.83,
            keywords: ["terminal", "window", "new", "shell"]
        ) { _ in
            try await TerminalManager.newWindow(command: nil)
            return .dismiss
        }
    }

    private static func runCommandAction(appIcon: String?) -> TerminalAction {
        TerminalAction(
            id: ActionID(module: "terminal", name: "runCommand"),
            title: "Run Command",
            subtitle: "Run a command in a new Terminal window",
            iconName: "text.cursor",
            appIconPath: appIcon,
            relevanceScore: 0.88,
            keywords: ["terminal", "run", "command", "execute", "shell"],
            parameters: [
                ActionParameter(
                    id: "command",
                    label: "Command",
                    type: .text(placeholder: "Enter command to run..."),
                    isRequired: true
                ),
            ]
        ) { values in
            guard let command = values["command"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !command.isEmpty
            else {
                return .showResult(title: "Run Command", body: "Please enter a command to run")
            }
            try await TerminalManager.newWindow(command: command)
            return .dismiss
        }
    }

    private static func commandActions(_ commands: [String: String], appIcon: String?) -> [TerminalAction] {
        commands.sorted { $0.key < $1.key }.map { name, command in
            TerminalAction(
                id: ActionID(module: "terminal", name: "cmd.\(StableID.hash(name))"),
                title: name,
                subtitle: command,
                iconName: "text.cursor",
                appIconPath: appIcon,
                relevanceScore: 0.86,
                keywords: ["terminal", "command", name.lowercased(), command.lowercased()]
            ) { _ in
                try await TerminalManager.newWindow(command: command)
                return .dismiss
            }
        }
    }
}
