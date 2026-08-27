import Foundation

/// Quick-launch actions for Codex and ChatGPT.
enum OpenAILaunchers {
    static func makeActions(config: OpenAIConfig) -> [AIAction] {
        var actions = [newCodexSession(config: config), newChatGPTChat()]
        if OpenAIDeeplink.isInstalled {
            actions.append(connectionSettings())
        }
        return actions
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

    private static func make(
        _ spec: AIAction.LauncherSpec,
        perform: @escaping @Sendable (ParameterValues) -> Void
    ) -> AIAction {
        .launcher(spec, module: OpenAIProvider.identity, perform: perform)
    }

    /// Starts a Codex session — in a terminal when `newSessionInTerminal` is set or
    /// the desktop app is missing, otherwise in the app.
    static func newCodexSession(config: OpenAIConfig) -> AIAction {
        let useTerminal = config.newSessionInTerminal
            || !OpenAIDeeplink.isInstalled
        return make(
            .init(
                name: "newCodex",
                title: "Start New Codex Session",
                subtitle: useTerminal
                    ? "Run `codex` in a fresh terminal tab"
                    : "Open a new session in the Codex app",
                icon: "plus.bubble",
                keywords: ["codex", "openai", "new", "start", "chat"],
                parameters: useTerminal ? [promptParam, cwdParam] : []
            )
        ) { values in
            guard useTerminal else {
                AILaunch.openApp(bundleID: OpenAIDeeplink.bundleID)
                return
            }
            let cli = OpenAIProvider.cli(config)
            let prompt = AILaunch.trimmed(values["prompt"])
            let command = prompt.map { "\(cli) \(AILaunch.shellQuote($0))" } ?? cli
            AILaunch.inTerminal(
                command: command,
                cwd: AILaunch.expandedPath(values["cwd"]),
                terminalApp: config.terminalApp
            )
        }
    }

    static func newChatGPTChat() -> AIAction {
        make(
            .init(
                name: "newChatGPT",
                title: "Start New ChatGPT Chat",
                subtitle: "Open chatgpt.com in browser",
                icon: "plus.bubble",
                keywords: ["chatgpt", "openai", "new", "start", "chat", "web"],
                parameters: [promptParam]
            )
        ) { values in
            AILaunch.url(
                "https://chatgpt.com/",
                query: ["q": AILaunch.trimmed(values["prompt"])]
            ).map(AILaunch.openURL)
        }
    }

    /// Jumps straight to the Codex app's connections settings, where MCP servers and
    /// integrations are managed.
    static func connectionSettings() -> AIAction {
        make(
            .init(
                name: "codexConnections",
                title: "Codex Connections",
                subtitle: "Manage Codex integrations and MCP servers",
                icon: "app.connected.to.app.below.fill",
                keywords: [
                    "codex", "settings", "connections", "mcp",
                    "integrations", "plugins",
                ]
            )
        ) { _ in
            AILaunch.openURL(OpenAIDeeplink.connectionSettings)
        }
    }
}
