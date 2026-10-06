import Foundation

struct ITermConfig: Codable, Sendable, Equatable {
    /// Maximum number of sessions to show in results (1–50).
    var maxResults: Int = 20

    /// Whether to show the current working directory in session subtitles.
    var showCWD: Bool = true

    /// Whether to show session job name (e.g. "vim", "ssh") in results.
    var showJobName: Bool = true

    /// Set of action name suffixes to expose (nil = all).
    var enabledActions: Set<String>?

    /// Predefined commands that appear as quick-run actions.
    /// Each entry maps a display name to a shell command string.
    var commands: [String: String]?

    /// Default profile name for new tabs/windows (nil = default profile).
    var defaultProfile: String?
}

extension ITermConfig {
    /// Every key is optional: a missing one keeps its default above instead of failing
    /// the whole section (see `ApplicationConfig`).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        maxResults = try container.decodeIfPresent(Int.self, forKey: .maxResults) ?? defaults.maxResults
        showCWD = try container.decodeIfPresent(Bool.self, forKey: .showCWD) ?? defaults.showCWD
        showJobName = try container.decodeIfPresent(Bool.self, forKey: .showJobName) ?? defaults.showJobName
        enabledActions = try container.decodeIfPresent(Set<String>.self, forKey: .enabledActions)
        commands = try container.decodeIfPresent([String: String].self, forKey: .commands)
        defaultProfile = try container.decodeIfPresent(String.self, forKey: .defaultProfile)
    }
}
