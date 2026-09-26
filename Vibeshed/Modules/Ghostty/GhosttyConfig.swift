import Foundation

struct GhosttyConfig: Codable, Sendable, Equatable {
    /// Maximum number of open terminals listed (1–50).
    var maxResults = 20

    /// Show each terminal's working directory in its subtitle.
    var showCWD = true

    /// Quick-run commands: display name → command typed into a new tab's shell.
    var commands: [String: String] = [:]

    /// Action name suffixes to expose (nil = all).
    var enabledActions: Set<String>?

    init() {}

    /// Decodes each field leniently: Codable synthesis ignores Swift property
    /// defaults, and a user's section may specify only some keys.
    init(from decoder: Decoder) throws {
        let defaults = GhosttyConfig()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maxResults = try container.decodeIfPresent(Int.self, forKey: .maxResults) ?? defaults.maxResults
        showCWD = try container.decodeIfPresent(Bool.self, forKey: .showCWD) ?? defaults.showCWD
        commands = try container.decodeIfPresent([String: String].self, forKey: .commands) ?? defaults.commands
        enabledActions = try container.decodeIfPresent(Set<String>.self, forKey: .enabledActions)
    }

    private enum CodingKeys: String, CodingKey {
        case maxResults
        case showCWD
        case commands
        case enabledActions
    }
}
