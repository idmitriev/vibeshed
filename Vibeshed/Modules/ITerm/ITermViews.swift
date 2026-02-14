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
        VStack(spacing: 12) {
            Image(systemName: previewIcon)
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

            if let path = action.sessionPath {
                Label(
                    abbreviatePath(path),
                    systemImage: "folder"
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
            }

            if let profile = action.profileName {
                Label(profile, systemImage: "person.circle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if let isAtPrompt = action.isAtPrompt {
                Label(
                    isAtPrompt ? "At shell prompt" : "Running job",
                    systemImage: isAtPrompt
                        ? "checkmark.circle" : "play.circle"
                )
                .font(.caption)
                .foregroundStyle(isAtPrompt ? .green : .orange)
            }

            Text("Module: iterm")
                .font(.caption)
                .foregroundStyle(.quaternary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
