import Foundation
import OSLog

/// Ghostty through its AppleScript dictionary (Ghostty 1.3+): open terminals as focus
/// actions, new windows and tabs, configured commands typed into a new tab, and a
/// config reload. Theming is the theme module's `ghostty` target.
actor GhosttyModule: ModuleConfigurable {
    let id = "ghostty"
    let displayName = "Ghostty"
    let iconName = "terminal"
    var isEnabled = true

    typealias Config = GhosttyConfig
    static var defaultConfig: Config? {
        .init()
    }

    static var automationTargets: [String] {
        [GhosttyApp.bundleID]
    }

    static let terminalPrefix = "terminal."

    private var config = GhosttyConfig()
    private let log = Log.module("ghostty")
    /// Listing runs an osascript subprocess — cache it so repeated picker fetches
    /// don't spawn AppleScript each time.
    private var terminalCache = TimedCache<[GhosttyTerminal]>(ttl: 5)

    func initialize(context _: ModuleContext) async throws {
        log.info("Ghostty module initialized")
    }

    func configDidUpdate(_ config: GhosttyConfig) async {
        self.config = config
    }

    static func validate(_ config: GhosttyConfig) -> ConfigValidationResult {
        (1 ... 50).contains(config.maxResults) ? .valid : .invalid(["maxResults must be between 1 and 50"])
    }

    func provideActions(query _: String, scoring _: ScoringContext) async -> [any Action] {
        let appIcon = GhosttyApp.appURL?.path
        let open = await terminals()
        let actions = Self.fixedActions(config: config, appIcon: appIcon)
            + Self.terminalActions(open, config: config, appIcon: appIcon)
        return Self.enabled(actions, config: config)
    }

    /// Everything but the terminal rows resolves without asking Ghostty for its
    /// terminals, so keybindings (checked at config load) never run a script.
    func action(id: ActionID) async -> (any Action)? {
        guard id.moduleID == self.id else { return nil }
        let appIcon = GhosttyApp.appURL?.path
        let fixed = Self.enabled(Self.fixedActions(config: config, appIcon: appIcon), config: config)
        if let action = fixed.first(where: { $0.id == id }) {
            return action
        }
        guard id.actionName.hasPrefix(Self.terminalPrefix) else { return nil }
        let rows = await Self.terminalActions(terminals(), config: config, appIcon: appIcon)
        return Self.enabled(rows, config: config).first { $0.id == id }
    }

    /// Failures (Ghostty too old, Automation denied) are cached like results, as an empty list.
    private func terminals() async -> [GhosttyTerminal] {
        if let cached = terminalCache.value {
            return cached
        }
        var terminals: [GhosttyTerminal] = []
        do {
            terminals = try await GhosttyManager.listTerminals()
        } catch let error as GhosttyApp.AppError {
            log.debug("Not listing terminals: \(error.localizedDescription, privacy: .public)")
        } catch {
            log.error("Failed to list Ghostty terminals: \(error.localizedDescription, privacy: .public)")
        }
        terminalCache.store(terminals)
        return terminals
    }

    /// `enabledActions` takes full names (`newTab`) or a family prefix (`cmd`, `terminal`).
    static func enabled(_ actions: [GhosttyAction], config: GhosttyConfig) -> [GhosttyAction] {
        guard let enabled = config.enabledActions else { return actions }
        return actions.filter { action in
            let name = action.id.actionName
            return enabled.contains(name) || enabled.contains(String(name.prefix { $0 != "." }))
        }
    }
}

// MARK: - Actions

extension GhosttyModule {
    static func fixedActions(config: GhosttyConfig, appIcon: String?) -> [GhosttyAction] {
        [
            newWindowAction(appIcon: appIcon),
            newTabAction(appIcon: appIcon),
            runCommandAction(appIcon: appIcon),
            reloadConfigAction(appIcon: appIcon),
        ] + commandActions(config.commands, appIcon: appIcon)
    }

    static func terminalActions(
        _ terminals: [GhosttyTerminal],
        config: GhosttyConfig,
        appIcon: String?
    ) -> [GhosttyAction] {
        terminals.prefix(config.maxResults).enumerated().map { index, terminal in
            var keywords = ["ghostty", "terminal", terminal.title.lowercased()]
            if let directory = terminal.workingDirectory {
                keywords += [directory.lowercased(), (directory as NSString).lastPathComponent.lowercased()]
            }
            let terminalID = terminal.id
            return GhosttyAction(
                id: ActionID(module: "ghostty", name: terminalPrefix + StableID.hash(terminal.id)),
                title: terminal.title.isEmpty ? "Terminal" : terminal.title,
                subtitle: terminalSubtitle(terminal, showCWD: config.showCWD),
                iconName: "terminal",
                appIconPath: appIcon,
                relevanceScore: max(0.3, 0.92 - Double(index) * 0.02),
                keywords: keywords,
                terminal: terminal
            ) { _ in
                try await GhosttyManager.focus(terminalID: terminalID)
                return .dismiss
            }
        }
    }

    /// Working directory (unless the title already shows it) and where the terminal is.
    static func terminalSubtitle(_ terminal: GhosttyTerminal, showCWD: Bool) -> String {
        var parts: [String] = []
        if showCWD, let directory = terminal.workingDirectory.map(abbreviatePath), directory != terminal.title {
            parts.append(directory)
        }
        parts.append(terminal.location)
        return parts.joined(separator: " · ")
    }

    private static func newWindowAction(appIcon: String?) -> GhosttyAction {
        GhosttyAction(
            id: ActionID(module: "ghostty", name: "newWindow"),
            title: "New Window",
            subtitle: "Open a new Ghostty window",
            iconName: "macwindow.badge.plus",
            appIconPath: appIcon,
            relevanceScore: 0.83,
            keywords: ["ghostty", "terminal", "window", "new", "shell"]
        ) { _ in
            try await GhosttyManager.newWindow(input: nil)
            return .dismiss
        }
    }

    private static func newTabAction(appIcon: String?) -> GhosttyAction {
        GhosttyAction(
            id: ActionID(module: "ghostty", name: "newTab"),
            title: "New Tab",
            subtitle: "Open a new Ghostty tab",
            iconName: "plus.rectangle",
            appIconPath: appIcon,
            relevanceScore: 0.85,
            keywords: ["ghostty", "terminal", "tab", "new", "shell"]
        ) { _ in
            try await GhosttyManager.newTab(input: nil)
            return .dismiss
        }
    }

    private static func runCommandAction(appIcon: String?) -> GhosttyAction {
        GhosttyAction(
            id: ActionID(module: "ghostty", name: "runCommand"),
            title: "Run Command",
            subtitle: "Run a command in a new Ghostty tab",
            iconName: "text.cursor",
            appIconPath: appIcon,
            relevanceScore: 0.88,
            keywords: ["ghostty", "terminal", "run", "command", "execute", "shell"],
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
            try await GhosttyManager.newTab(input: command)
            return .dismiss
        }
    }

    private static func reloadConfigAction(appIcon: String?) -> GhosttyAction {
        GhosttyAction(
            id: ActionID(module: "ghostty", name: "reloadConfig"),
            title: "Reload Configuration",
            subtitle: "Make Ghostty re-read its config files",
            iconName: "arrow.clockwise",
            appIconPath: appIcon,
            relevanceScore: 0.7,
            keywords: ["ghostty", "reload", "config", "configuration", "settings", "refresh"]
        ) { _ in
            guard GhosttyApp.isRunning else {
                return .showResult(title: "Reload Configuration", body: "Ghostty isn't running")
            }
            guard GhosttyApp.reloadConfig().outdated == 0 else {
                return .showResult(
                    title: "Reload Configuration",
                    body: "This Ghostty is too old to reload from outside — press ⌘⇧, in Ghostty"
                )
            }
            return .dismiss
        }
    }

    /// Configured commands, typed into a new tab's shell so it stays open afterwards.
    private static func commandActions(_ commands: [String: String], appIcon: String?) -> [GhosttyAction] {
        commands.sorted { $0.key < $1.key }.map { name, command in
            GhosttyAction(
                id: ActionID(module: "ghostty", name: "cmd.\(StableID.hash(name))"),
                title: name,
                subtitle: command,
                iconName: "text.cursor",
                appIconPath: appIcon,
                relevanceScore: 0.86,
                keywords: ["ghostty", "command", name.lowercased(), command.lowercased()]
            ) { _ in
                try await GhosttyManager.newTab(input: command)
                return .dismiss
            }
        }
    }
}
