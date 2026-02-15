import Foundation
import SwiftUI

enum TelegramItemType: String, Sendable {
    case chat
    case utility
}

struct TelegramAction: Action {
    let id: ActionID
    let title: String
    let subtitle: String
    let iconName: String?
    let relevanceScore: Double
    let keywords: [String]
    let parameters: [ActionParameter]

    let telegramItemType: TelegramItemType?
    let chatType: TelegramChatType?

    private let runner: @Sendable (
        [String: Any]
    ) async throws -> ActionResult

    init(
        id: ActionID,
        title: String,
        subtitle: String,
        iconName: String? = nil,
        relevanceScore: Double = 0.8,
        keywords: [String] = [],
        parameters: [ActionParameter] = [],
        telegramItemType: TelegramItemType? = nil,
        chatType: TelegramChatType? = nil,
        runner: @escaping @Sendable (
            [String: Any]
        ) async throws -> ActionResult
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.relevanceScore = relevanceScore
        self.keywords = keywords
        self.parameters = parameters
        self.telegramItemType = telegramItemType
        self.chatType = chatType
        self.runner = runner
    }

    func run(with values: [String: Any]) async throws -> ActionResult {
        try await runner(values)
    }

    @MainActor
    func makeListItemView() -> AnyView? {
        AnyView(TelegramActionListItemView(action: self))
    }

    @MainActor
    func makePreviewView() -> AnyView? {
        AnyView(TelegramActionPreviewView(action: self))
    }
}
