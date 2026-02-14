import Foundation

struct AIConfig: Codable, Sendable, Equatable {
    /// Maximum number of recent sessions to show per provider (1–100).
    var maxResults: Int = 20

    /// Which providers to scan: "claudeCode", "claudeDesktop", "codex".
    var providers: [String] = ["claudeCode", "claudeDesktop", "codex"]

    /// Set of action name suffixes to expose (nil = all).
    var enabledActions: Set<String>?

    /// Whether to show quick-launch actions for desktop apps
    /// (Claude Desktop, ChatGPT web, Codex Desktop).
    var showLaunchers: Bool = true

    /// Custom path to the `claude` CLI binary.
    var claudePath: String?

    /// Terminal app to use for resuming CLI sessions: "iterm" or "terminal".
    var terminalApp: String?
}
