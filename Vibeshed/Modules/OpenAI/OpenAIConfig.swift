import Foundation

struct OpenAIConfig: AIProviderConfig {
    /// Maximum number of recent sessions to show (1–100).
    var maxResults: Int = 20

    /// Which surfaces to scan: "codex".
    var sources: [String] = [OpenAIProvider.codex.id]

    /// Set of action name suffixes to expose (nil = all).
    var enabledActions: Set<String>?

    /// Whether to show quick-launch actions (new session, settings, …).
    var showLaunchers: Bool = true

    /// Start new sessions in a terminal running the `codex` CLI rather than in the
    /// desktop app. Existing sessions always reopen in the app, which is the only
    /// surface that can address a thread by id.
    var newSessionInTerminal: Bool = false

    /// Custom path to the `codex` CLI binary.
    var codexPath: String?

    /// Terminal app for CLI sessions: "iterm" or "terminal".
    var terminalApp: String?

    init() {}

    /// Decodes every field with `decodeIfPresent` so a config section written before a
    /// field was added still decodes rather than throwing `keyNotFound`, which
    /// `ModuleConfigDecoder` would swallow by discarding the whole section.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = OpenAIConfig()
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
        newSessionInTerminal = try container.decodeIfPresent(
            Bool.self, forKey: .newSessionInTerminal
        ) ?? defaults.newSessionInTerminal
        codexPath = try container.decodeIfPresent(String.self, forKey: .codexPath)
        terminalApp = try container.decodeIfPresent(
            String.self, forKey: .terminalApp
        )
    }
}
