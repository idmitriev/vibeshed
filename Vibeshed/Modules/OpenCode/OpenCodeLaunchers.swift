import Foundation

/// Quick-launch actions for OpenCode.
enum OpenCodeLaunchers {
    static func makeActions(config: OpenCodeConfig) -> [AIAction] {
        [newSession(config: config)]
    }

    private static let promptParam = ActionParameter(
        id: "prompt",
        label: "Prompt",
        type: .text(placeholder: "What would you like to ask?"),
        isRequired: false
    )

    private static let cwdParam = ActionParameter(
        id: "cwd",
        label: "Working directory",
        type: .text(placeholder: "~/Projects/..."),
        isRequired: false
    )

    /// Starts an OpenCode session in a fresh terminal tab. The desktop app has no URL
    /// for a new session, so this always uses the CLI.
    static func newSession(config: OpenCodeConfig) -> AIAction {
        .launcher(
            .init(
                name: "newOpenCode",
                title: "Start New OpenCode Session",
                subtitle: "Run `opencode` in a fresh terminal tab",
                icon: "plus.bubble",
                keywords: ["opencode", "new", "start", "chat", "terminal"],
                parameters: [promptParam, cwdParam]
            ),
            module: OpenCodeProvider.identity
        ) { values in
            let cli = OpenCodeProvider.cli(config)
            let prompt = AILaunch.trimmed(values["prompt"])
            let command = prompt.map { "\(cli) --prompt \(AILaunch.shellQuote($0))" } ?? cli
            AILaunch.inTerminal(
                command: command,
                cwd: AILaunch.expandedPath(values["cwd"]),
                terminalApp: config.terminalApp
            )
        }
    }
}
