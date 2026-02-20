import SwiftUI

struct AIActionListItemView: View {
    let action: AIAction

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.iconName ?? "brain")
                .font(.title3)
                .foregroundStyle(colorForProvider)
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
                if let provider = action.provider {
                    Text(providerShortLabel(provider))
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
                if let timestamp = action.sessionTimestamp {
                    Text(relativeTime(timestamp))
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var colorForProvider: Color {
        guard let provider = action.provider else {
            return .secondary
        }
        switch provider {
        case .claudeCode: return .orange
        case .claudeDesktop: return .purple
        case .codex: return .green
        }
    }
}

struct AIActionPreviewView: View {
    let action: AIAction

    var body: some View {
        PreviewLayout(moduleName: "ai") {
            PreviewHeader(
                title: action.title,
                subtitle: action.subtitle,
                systemIcon: action.iconName ?? "brain",
                iconColor: previewColor
            )

            if let provider = action.provider {
                PreviewPill(
                    text: providerFullLabel(provider),
                    icon: providerIcon(provider),
                    color: previewColor
                )
            }

            if let path = action.projectPath {
                PreviewMetadataRow(
                    icon: "folder",
                    label: "Project",
                    value: abbreviatePath(path)
                )
            }

            if let model = action.modelName {
                PreviewMetadataRow(
                    icon: "cpu",
                    label: "Model",
                    value: model
                )
            }

            if let timestamp = action.sessionTimestamp {
                PreviewMetadataRow(
                    icon: "clock",
                    label: "Session",
                    value: formatDate(timestamp)
                )
            }
        }
    }

    private var previewColor: Color {
        guard let provider = action.provider else {
            return .secondary
        }
        switch provider {
        case .claudeCode: return .orange
        case .claudeDesktop: return .purple
        case .codex: return .green
        }
    }
}

// MARK: - Helpers

private func providerShortLabel(_ provider: AIProvider) -> String {
    switch provider {
    case .claudeCode: "CODE"
    case .claudeDesktop: "DESKTOP"
    case .codex: "CODEX"
    }
}

private func providerFullLabel(_ provider: AIProvider) -> String {
    switch provider {
    case .claudeCode: "Claude Code"
    case .claudeDesktop: "Claude Desktop"
    case .codex: "Codex CLI"
    }
}

private func providerIcon(_ provider: AIProvider) -> String {
    switch provider {
    case .claudeCode: "terminal"
    case .claudeDesktop: "brain"
    case .codex: "terminal.fill"
    }
}

private func relativeTime(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
}

private func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

private func abbreviatePath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if path.hasPrefix(home) {
        return "~" + path.dropFirst(home.count)
    }
    return path
}
