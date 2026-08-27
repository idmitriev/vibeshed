import Foundation

/// Quick-launch actions for Claude: starting new sessions and jumping into the
/// desktop app's Claude Code surfaces.
enum AnthropicLaunchers {
    static func makeActions(config: AnthropicConfig) -> [AIAction] {
        var actions = [newClaudeCode(config: config), newChat()]
        // The remaining entries are desktop-app deeplinks with no web equivalent.
        if AnthropicDeeplink.isInstalled {
            actions.append(contentsOf: [continueLast(), needsInput()])
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
        .launcher(spec, module: AnthropicProvider.identity, perform: perform)
    }

    // MARK: - New sessions

    /// Starts a Claude Code session, honouring `resumeIn` for whether that means a
    /// terminal tab or the desktop app.
    static func newClaudeCode(config: AnthropicConfig) -> AIAction {
        let useDesktop = config.resumeIn == .desktop
            && AnthropicDeeplink.isInstalled
        return make(
            .init(
                name: "newClaudeCode",
                title: "Start New Claude Code Session",
                subtitle: useDesktop
                    ? "Open a new Claude Code session in the desktop app"
                    : "Run `claude` in a fresh terminal tab",
                icon: "plus.bubble",
                keywords: [
                    "claude", "code", "cli", "new", "start", "chat", "terminal",
                ],
                parameters: [promptParam, cwdParam]
            )
        ) { values in
            let cwd = AILaunch.expandedPath(values["cwd"])
            let prompt = AILaunch.trimmed(values["prompt"])

            if useDesktop,
               let url = AnthropicDeeplink.newCodeSession(
                   prompt: prompt, folder: cwd
               )
            {
                AILaunch.openURL(url)
                return
            }
            let cli = AnthropicProvider.cli(config)
            let command = prompt.map { "\(cli) \(AILaunch.shellQuote($0))" } ?? cli
            AILaunch.inTerminal(
                command: command, cwd: cwd, terminalApp: config.terminalApp
            )
        }
    }

    /// A new Claude chat — through the desktop app when installed, else the web app.
    static func newChat() -> AIAction {
        make(
            .init(
                name: "newClaudeChat",
                title: "Start New Claude Chat",
                subtitle: AnthropicDeeplink.isInstalled
                    ? "Open a new chat in Claude Desktop"
                    : "Open claude.ai/new in browser",
                icon: "plus.bubble",
                keywords: [
                    "claude", "anthropic", "desktop", "new", "start", "chat",
                ],
                parameters: [promptParam]
            )
        ) { values in
            let prompt = AILaunch.trimmed(values["prompt"])
            let url = AnthropicDeeplink.isInstalled
                ? AnthropicDeeplink.newChat(prompt: prompt)
                : AILaunch.url("https://claude.ai/new", query: ["q": prompt])
            url.map(AILaunch.openURL)
        }
    }

    // MARK: - Desktop jump-ins

    static func continueLast() -> AIAction {
        make(
            .init(
                name: "continueLastClaudeCode",
                title: "Continue Last Claude Code Session",
                subtitle: "Reopen the most recent session in Claude Desktop",
                icon: "arrow.uturn.backward",
                keywords: [
                    "claude", "code", "continue", "last", "resume", "recent",
                ]
            )
        ) { _ in
            AnthropicDeeplink.continueLast.map(AILaunch.openURL)
        }
    }

    /// Jumps to the session that has waited longest for a permission answer — a
    /// blocked agent is otherwise easy to lose track of.
    static func needsInput() -> AIAction {
        make(
            .init(
                name: "claudeCodeNeedsInput",
                title: "Claude Code Sessions Waiting for You",
                subtitle: "Jump to a session waiting on a permission answer",
                icon: "bell.badge",
                keywords: [
                    "claude", "code", "waiting", "input", "permission",
                    "blocked", "needs",
                ]
            )
        ) { _ in
            AnthropicDeeplink.needsInput.map(AILaunch.openURL)
        }
    }
}
