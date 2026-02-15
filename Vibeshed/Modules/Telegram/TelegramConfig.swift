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
