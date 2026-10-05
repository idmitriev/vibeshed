import Foundation

enum TelegramChatType: String, Codable, Sendable, Equatable {
    case chat
    case group
    case channel
}

struct TelegramChatEntry: Codable, Sendable, Equatable {
    let name: String
    var username: String?
    var phone: String?
    var icon: String?
    var keywords: [String]?
    var type: TelegramChatType?
}

struct TelegramConfig: Codable, Sendable, Equatable {
    var chats: [TelegramChatEntry] = []
    var showLaunchAction: Bool = true
    var showSavedMessages: Bool = true
    var enabledActions: Set<String>?
}

extension TelegramConfig {
    /// Every key is optional: a missing one keeps its default above instead of failing
    /// the whole section (see `ApplicationConfig`).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        chats = try container.decodeIfPresent([TelegramChatEntry].self, forKey: .chats) ?? defaults.chats
        showLaunchAction = try container.decodeIfPresent(Bool.self, forKey: .showLaunchAction)
            ?? defaults.showLaunchAction
        showSavedMessages = try container.decodeIfPresent(Bool.self, forKey: .showSavedMessages)
            ?? defaults.showSavedMessages
        enabledActions = try container.decodeIfPresent(Set<String>.self, forKey: .enabledActions)
    }
}
