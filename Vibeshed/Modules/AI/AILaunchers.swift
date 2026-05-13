import AppKit
import Foundation

enum AILaunchers {
    static func makeActions(config: AIConfig) -> [AIAction] {
        let providers = Set(config.providers)
        var actions: [AIAction] = []
        if providers.contains("claudeCode") {
            actions.append(makeClaudeCodeAction(config: config))
        }
        if providers.contains("claudeDesktop") {
            actions.append(makeClaudeAction())
        }
        if providers.contains("codex") {
            actions.append(makeCodexAction())
        }
        actions.append(makeChatGPTAction())
        return actions
    }

    private static let promptParam = ActionParameter(
        id: "prompt",
        label: "Prompt",
        type: .text(placeholder: "What would you like to ask?"),
        isRequired: false
    )

    static func makeClaudeCodeAction(config: AIConfig) -> AIAction {
        AIAction(
            id: ActionID(module: "ai", name: "newClaudeCode"),
            title: "Start New Claude Code Chat",
            subtitle: "Run `claude` in a fresh terminal tab",
            iconName: "plus.bubble",
            relevanceScore: 0.7,
            keywords: [
                "ai", "claude", "code", "cli", "new",
                "start", "chat", "terminal",
            ],
            parameters: [
                promptParam,
                ActionParameter(
                    id: "cwd",
                    label: "Working directory",
                    type: .text(placeholder: "~/Projects/..."),
                    isRequired: false
                ),
            ],
            aiItemType: .launcher
        ) { [config] values in
            let cwd = expandedCwd(values["cwd"])
            let prompt = trimmedString(values["prompt"])
            let cli = AIModule.resolveClaudeCLI(
                customPath: config.claudePath
            )
            let command: String
            if let prompt, !prompt.isEmpty {
                command = "\(cli) \(shellQuote(prompt))"
            } else {
                command = cli
            }
            AIModule.launchInTerminal(
                command: command,
                cwd: cwd,
                terminalApp: config.terminalApp
            )
            return .dismiss
        }
    }

    static func makeClaudeAction() -> AIAction {
        AIAction(
            id: ActionID(module: "ai", name: "newClaudeDesktop"),
            title: "Start New Claude Chat",
            subtitle: "Open claude.ai/new in browser",
            iconName: "plus.bubble",
            relevanceScore: 0.7,
            keywords: [
                "ai", "claude", "desktop", "anthropic",
                "new", "start", "chat",
            ],
            parameters: [promptParam],
            aiItemType: .launcher
        ) { values in
            openWebChat(
                base: "https://claude.ai/new",
                prompt: trimmedString(values["prompt"])
            )
            return .dismiss
        }
    }

    static func makeCodexAction() -> AIAction {
        AIAction(
            id: ActionID(module: "ai", name: "newCodex"),
            title: "Start New Codex Chat",
            subtitle: "Open chatgpt.com/codex in browser",
            iconName: "plus.bubble",
            relevanceScore: 0.7,
            keywords: [
                "ai", "codex", "openai", "new",
                "start", "chat",
            ],
            parameters: [promptParam],
            aiItemType: .launcher
        ) { values in
            openWebChat(
                base: "https://chatgpt.com/codex",
                prompt: trimmedString(values["prompt"])
            )
            return .dismiss
        }
    }

    static func makeChatGPTAction() -> AIAction {
        AIAction(
            id: ActionID(module: "ai", name: "newChatGPT"),
            title: "Start New ChatGPT Chat",
            subtitle: "Open chatgpt.com in browser",
            iconName: "plus.bubble",
            relevanceScore: 0.7,
            keywords: [
                "ai", "chatgpt", "openai", "new",
                "start", "chat", "web",
            ],
            parameters: [promptParam],
            aiItemType: .launcher
        ) { values in
            openWebChat(
                base: "https://chatgpt.com/",
                prompt: trimmedString(values["prompt"])
            )
            return .dismiss
        }
    }

    // MARK: - Helpers

    private static func trimmedString(_ value: Any?) -> String? {
        let trimmed = (value as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty { return trimmed }
        return nil
    }

    private static func expandedCwd(_ value: Any?) -> String? {
        guard let raw = trimmedString(value) else { return nil }
        return (raw as NSString).expandingTildeInPath
    }

    /// POSIX shell single-quote escape: wraps in `'…'`,
    /// replacing any embedded `'` with `'\''`.
    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    @Sendable
    private static func openWebChat(base: String, prompt: String?) {
        guard var components = URLComponents(string: base) else { return }
        if let prompt {
            components.queryItems = [URLQueryItem(name: "q", value: prompt)]
        }
        guard let url = components.url else { return }
        DispatchQueue.main.async {
            NSWorkspace.shared.open(url)
        }
    }
}
