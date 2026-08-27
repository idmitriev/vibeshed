import Foundation

/// Where a Claude Code session should reopen when it can be resumed either way.
enum AnthropicResumeTarget: String, Codable, Sendable {
    /// Run `claude --resume <id>` in a terminal tab.
    case terminal
    /// Hand the session to Claude Desktop via a `claude://` deeplink.
    case desktop
}

struct AnthropicConfig: AIProviderConfig {
    /// Maximum number of recent sessions to show (1–100).
    var maxResults: Int = 20

    /// Which surfaces to scan: "claudeCode", "claudeDesktop".
    var sources: [String] = [
        AnthropicProvider.claudeCode.id,
        AnthropicProvider.claudeDesktop.id,
    ]

    /// Set of action name suffixes to expose (nil = all).
    var enabledActions: Set<String>?

    /// Whether to show quick-launch actions (new chat, continue last, …).
    var showLaunchers: Bool = true

    /// Where CLI sessions reopen by default.
    var resumeIn: AnthropicResumeTarget = .terminal

    /// Also list each session's other surface as its own row — a CLI session handed
    /// to Claude Desktop, or a desktop session dropped into a terminal. Off by
    /// default because it doubles the number of session rows in the picker.
    var showAlternateResume: Bool = false

    /// Custom path to the `claude` CLI binary.
    var claudePath: String?

    /// Terminal app for CLI sessions: "iterm" or "terminal".
    var terminalApp: String?

    init() {}

    /// Decodes every field with `decodeIfPresent` so a config section that predates a
    /// newly added field still decodes instead of throwing `keyNotFound` — which
    /// `ModuleConfigDecoder` would otherwise swallow, silently discarding the whole
    /// user section back to defaults.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AnthropicConfig()
        maxResults = try container.decodeIfPresent(
            Int.self, forKey: .maxResults
        ) ?? defaults.maxResults
        sources = try container.decodeIfPresent(
            [String].self, forKey: .sources
        ) ?? defaults.sources
        enabledActions = try container.decodeIfPresent(
            Set<String>.self, forKey: .enabledActions
        )
        showLaunchers = try container.decodeIfPresent(
            Bool.self, forKey: .showLaunchers
        ) ?? defaults.showLaunchers
        resumeIn = try container.decodeIfPresent(
            AnthropicResumeTarget.self, forKey: .resumeIn
        ) ?? defaults.resumeIn
        showAlternateResume = try container.decodeIfPresent(
            Bool.self, forKey: .showAlternateResume
        ) ?? defaults.showAlternateResume
        claudePath = try container.decodeIfPresent(
            String.self, forKey: .claudePath
        )
        terminalApp = try container.decodeIfPresent(
            String.self, forKey: .terminalApp
        )
    }
}
