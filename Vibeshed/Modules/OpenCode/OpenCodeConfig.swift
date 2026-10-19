import Foundation

struct OpenCodeConfig: AIProviderConfig {
    /// Maximum number of recent sessions to show (1–100).
    var maxResults: Int = 20

    /// Which surfaces to scan: "opencode".
    var sources: [String] = [OpenCodeProvider.opencode.id]

    /// Set of action name suffixes to expose (nil = all).
    var enabledActions: Set<String>?

    /// Whether to show quick-launch actions (new session).
    var showLaunchers: Bool = true

    /// Custom path to the `opencode` CLI binary.
    var opencodePath: String?

    /// Terminal app for CLI sessions: "iterm" or "terminal".
    var terminalApp: String?

    init() {}

    /// Decodes every field with `decodeIfPresent` so a config section written before a
    /// field was added still decodes rather than throwing `keyNotFound`, which
    /// `ModuleConfigDecoder` would swallow by discarding the whole section.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = OpenCodeConfig()
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
        opencodePath = try container.decodeIfPresent(
            String.self, forKey: .opencodePath
        )
        terminalApp = try container.decodeIfPresent(
            String.self, forKey: .terminalApp
        )
    }
}
