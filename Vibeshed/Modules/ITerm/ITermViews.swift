import SwiftUI

struct ITermActionListItemView: View {
    let action: ITermAction

    var body: some View {
        HStack(spacing: 10) {
            iconView
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

            HStack(spacing: 4) {
                if let isAtPrompt = action.isAtPrompt {
                    promptIndicator(isAtPrompt)
                }
                if let itemType = action.itermItemType {
                    typeLabel(itemType)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var iconView: some View {
        Image(systemName: iconForAction)
            .font(.title3)
            .foregroundStyle(colorForType)
    }

    private var iconForAction: String {
        action.iconName ?? itemTypeIcon(action.itermItemType)
    }

    private var colorForType: Color {
        switch action.itermItemType {
        case .session: .green
        case .newTab: .blue
        case .newWindow: .blue
        case .command: .orange
        case nil: .secondary
        }
    }

    @ViewBuilder
    private func promptIndicator(_ atPrompt: Bool) -> some View {
        Circle()
            .fill(atPrompt ? .green : .orange)
            .frame(width: 6, height: 6)
    }

    @ViewBuilder
    private func typeLabel(_ type: ITermItemType) -> some View {
        if type == .session, let job = action.jobName {
            Text(job)
                .font(.caption2)
                .foregroundStyle(.quaternary)
        }
    }
}

struct ITermActionPreviewView: View {
    let action: ITermAction

    var body: some View {
        PreviewLayout(moduleName: "iterm") {
            Image(systemName: previewIcon)
                .font(.system(size: 48))
                .foregroundStyle(previewColor)
                .frame(maxWidth: .infinity)
                .frame(height: 56)

            Text(action.title)
                .font(.title3)
                .fontWeight(.medium)
                .lineLimit(2)

            if !action.subtitle.isEmpty {
                Text(action.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if let isAtPrompt = action.isAtPrompt {
                PreviewPill(
                    text: isAtPrompt ? "At shell prompt" : "Running job",
                    icon: isAtPrompt ? "checkmark.circle" : "play.circle",
                    color: isAtPrompt ? .green : .orange
                )
            }

            if let path = action.sessionPath {
                PreviewMetadataRow(
                    icon: "folder",
                    label: "Path",
                    value: abbreviatePath(path)
                )
            }

            if let profile = action.profileName {
                PreviewMetadataRow(
                    icon: "person.circle",
                    label: "Profile",
                    value: profile
                )
            }
        }
    }

    private var previewIcon: String {
        action.iconName ?? itemTypeIcon(action.itermItemType)
    }

    private var previewColor: Color {
        switch action.itermItemType {
        case .session: .green
        case .newTab, .newWindow: .blue
        case .command: .orange
        case nil: .secondary
        }
    }
}

// MARK: - Helpers

private func itemTypeIcon(_ type: ITermItemType?) -> String {
    switch type {
    case .session: "terminal"
    case .newTab: "plus.rectangle"
    case .newWindow: "macwindow.badge.plus"
    case .command: "text.cursor"
    case nil: "terminal"
    }
}

private func abbreviatePath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if path.hasPrefix(home) {
        return "~" + path.dropFirst(home.count)
    }
    return path
}
