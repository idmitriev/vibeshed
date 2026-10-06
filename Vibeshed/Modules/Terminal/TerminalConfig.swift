import Foundation

struct TerminalConfig: Codable, Sendable, Equatable {
    /// Quick-run commands: display name → command run in a new window's shell.
    var commands: [String: String] = [:]

    /// Action name suffixes to expose (nil = all).
    var enabledActions: Set<String>?

    init() {}

    /// Decodes each field leniently: Codable synthesis ignores Swift property
    /// defaults, and a user's section may specify only some keys.
    init(from decoder: Decoder) throws {
        let defaults = TerminalConfig()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        commands = try container.decodeIfPresent([String: String].self, forKey: .commands) ?? defaults.commands
        enabledActions = try container.decodeIfPresent(Set<String>.self, forKey: .enabledActions)
    }

    private enum CodingKeys: String, CodingKey {
        case commands
        case enabledActions
    }
}
