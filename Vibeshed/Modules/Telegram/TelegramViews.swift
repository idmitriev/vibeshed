import SwiftUI

struct TelegramActionListItemView: View {
    let action: TelegramAction

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.iconName ?? iconForType)
                .font(.title3)
                .foregroundStyle(colorForType)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.body)
                    .lineLimit(1)

                if !action.subtitle.isEmpty {
                    Text(action.subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let chatType = action.chatType {
                Text(chatTypeLabel(chatType))
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var iconForType: String {
        guard let chatType = action.chatType else {
            return "paperplane.fill"
        }
        return iconForChatType(chatType)
    }

    private var colorForType: Color {
        switch action.telegramItemType {
        case .chat: return .blue
        case .utility: return .secondary
        case nil: return .secondary
        }
    }
}

struct TelegramActionPreviewView: View {
    let action: TelegramAction

    var body: some View {
        PreviewLayout(moduleName: "telegram") {
            PreviewHeader(
                title: action.title,
                subtitle: action.subtitle,
                systemIcon: action.iconName ?? previewIcon,
                iconColor: previewColor
            )

            if let chatType = action.chatType {
                PreviewPill(
                    text: chatTypeLabel(chatType),
                    icon: iconForChatType(chatType),
                    color: previewColor
                )
            }
        }
    }

    private var previewIcon: String {
        guard let chatType = action.chatType else {
            return "paperplane.fill"
        }
        return iconForChatType(chatType)
    }

    private var previewColor: Color {
        switch action.telegramItemType {
        case .chat: return .blue
        case .utility: return .secondary
        case nil: return .secondary
        }
    }
}

// MARK: - Helpers

private func iconForChatType(_ type: TelegramChatType) -> String {
    switch type {
    case .chat: return "person.fill"
    case .group: return "person.3.fill"
    case .channel: return "megaphone.fill"
    }
}

private func chatTypeLabel(_ type: TelegramChatType) -> String {
    switch type {
    case .chat: return "Chat"
    case .group: return "Group"
    case .channel: return "Channel"
    }
}
