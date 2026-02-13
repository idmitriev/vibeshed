import SwiftUI

struct GitHubActionListItemView: View {
    let action: GitHubAction

    var body: some View {
        HStack(spacing: 10) {
            avatarOrIcon
                .frame(width: 28, height: 28)
                .clipShape(Circle())

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

            HStack(spacing: 4) {
                if let stateIcon = action.stateIcon,
                   let stateColor = action.stateColor {
                    Image(systemName: stateIcon)
                        .font(.caption)
                        .foregroundStyle(stateColor)
                }
                if let itemType = action.githubItemType {
                    Text(itemType.rawValue.uppercased())
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var avatarOrIcon: some View {
        if let avatarURL = action.avatarURL,
           let url = URL(string: avatarURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    fallbackIcon
                }
            }
        } else {
            fallbackIcon
        }
    }

    private var fallbackIcon: some View {
        Image(
            systemName: action.iconName
                ?? "chevron.left.forwardslash.chevron.right"
        )
        .font(.title3)
        .foregroundStyle(.secondary)
    }
}

struct GitHubActionPreviewView: View {
    let action: GitHubAction

    var body: some View {
        VStack(spacing: 12) {
            previewAvatarOrIcon
                .frame(width: 64, height: 64)
                .clipShape(Circle())

            Text(action.title)
                .font(.title2)
                .multilineTextAlignment(.center)

            Text(action.subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let stateIcon = action.stateIcon,
               let stateColor = action.stateColor {
                Label(stateLabel, systemImage: stateIcon)
                    .font(.caption)
                    .foregroundStyle(stateColor)
            }

            if let itemType = action.githubItemType {
                Label(
                    typeLabel(for: itemType),
                    systemImage: iconForType(itemType)
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
            }

            Text("Module: github")
                .font(.caption)
                .foregroundStyle(.quaternary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var previewAvatarOrIcon: some View {
        if let avatarURL = action.avatarURL,
           let url = URL(string: avatarURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    previewFallbackIcon
                }
            }
        } else {
            previewFallbackIcon
        }
    }

    private var previewFallbackIcon: some View {
        Image(
            systemName: action.iconName
                ?? "chevron.left.forwardslash.chevron.right"
        )
        .font(.largeTitle)
        .foregroundStyle(.secondary)
    }

    private var stateLabel: String {
        if let icon = action.stateIcon {
            switch icon {
            case "circle.fill": return "Open"
            case "checkmark.circle.fill": return "Closed"
            case "arrow.triangle.pull": return "Open"
            case "arrow.triangle.merge": return "Merged"
            case "xmark.circle.fill": return "Closed"
            case "doc": return "Draft"
            default: return ""
            }
        }
        return ""
    }
}

private func iconForType(_ type: GitHubItemType) -> String {
    switch type {
    case .repo: "folder"
    case .issue: "exclamationmark.circle"
    case .pr: "arrow.triangle.pull"
    case .notification: "bell"
    }
}

private func typeLabel(for type: GitHubItemType) -> String {
    switch type {
    case .repo: "Repository"
    case .issue: "Issue"
    case .pr: "Pull Request"
    case .notification: "Notification"
    }
}
