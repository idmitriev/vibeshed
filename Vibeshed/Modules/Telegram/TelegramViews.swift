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
        VStack(spacing: 12) {
            Image(systemName: action.iconName ?? previewIcon)
                .font(.largeTitle)
                .foregroundStyle(previewColor)
                .frame(width: 64, height: 64)

            Text(action.title)
                .font(.title2)
                .multilineTextAlignment(.center)

            if !action.subtitle.isEmpty {
                Text(action.subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let chatType = action.chatType {
                Label(
                    chatTypeLabel(chatType),
                    systemImage: iconForChatType(chatType)
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
            }

            Text("Module: telegram")
                .font(.caption)
                .foregroundStyle(.quaternary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
