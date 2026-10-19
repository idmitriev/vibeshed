import Foundation

/// OpenCode sessions, from both the CLI and the OpenCode desktop app — they share one
/// SQLite store under `~/.local/share/opencode`.
///
/// Sessions always reopen in a terminal: the desktop app registers `opencode://` but
/// only acts on its sign-in callback, so no URL can open a session there.
struct OpenCodeProvider: AIProvider {
    typealias Config = OpenCodeConfig

    static let moduleID = "opencode"
    static let displayName = "OpenCode"
    static let iconName = "chevron.left.forwardslash.chevron.right"
    static let defaultConfig = OpenCodeConfig()

    /// The Electron desktop app, which bundles its own CLI.
    static let appBundleID = "ai.opencode.desktop"

    static let opencode = AISessionSource(
        id: "opencode",
        shortLabel: "OPENCODE",
        fullLabel: "OpenCode",
        iconName: "chevron.left.forwardslash.chevron.right",
        accent: .teal
    )

    static let allSources = [opencode]

    static func validate(_ config: OpenCodeConfig) -> ConfigValidationResult {
        var errors = validateCommon(config).errors
        if let path = config.opencodePath, !path.isEmpty,
           !FileManager.default.fileExists(atPath: path)
        {
            errors.append("opencodePath does not exist: \(path)")
        }
        if let terminal = config.terminalApp,
           !["iterm", "terminal"].contains(terminal)
        {
            errors.append(
                "Invalid terminalApp: '\(terminal)'. Valid: iterm, terminal"
            )
        }
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    // MARK: - Sessions

    func readSessions(config: OpenCodeConfig, limit: Int) -> [AISession] {
        guard config.sources.contains(Self.opencode.id) else { return [] }
        return OpenCodeSessionReader.readSessions(limit: limit)
    }

    /// Runs `opencode --session <id>` from the session's directory. The CLI scopes
    /// sessions to the project it starts in, so the directory matters.
    func openSession(_ session: AISession, config: OpenCodeConfig) {
        AILaunch.inTerminal(
            command: Self.resumeCommand(cli: Self.cli(config), sessionID: session.sessionID),
            cwd: session.project,
            terminalApp: config.terminalApp
        )
    }

    static func resumeCommand(cli: String, sessionID: String) -> String {
        "\(cli) --session \(AILaunch.shellQuote(sessionID))"
    }

    /// Prefers a standalone install, which `opencode upgrade` keeps current, over the
    /// copy bundled inside the desktop app.
    static func cli(_ config: OpenCodeConfig) -> String {
        AILaunch.resolveCLI(
            customPath: config.opencodePath,
            candidates: [
                NSHomeDirectory() + "/.opencode/bin/opencode",
                "/opt/homebrew/bin/opencode",
                "/usr/local/bin/opencode",
                "/Applications/OpenCode.app/Contents/Resources/opencode-cli",
            ],
            fallbackName: "opencode"
        )
    }

    // MARK: - Launchers

    func launcherActions(config: OpenCodeConfig) -> [AIAction] {
        OpenCodeLaunchers.makeActions(config: config)
    }
}
