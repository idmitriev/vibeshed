import SwiftUI

struct VSCodeActionListItemView: View {
    let action: VSCodeAction

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
                if let itemType = action.vscodeItemType {
                    typeIndicator(itemType)
                }
                if let variant = action.variant,
                   variant != "VS Code" {
                    Text(variant)
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
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
        action.iconName ?? typeIcon(action.vscodeItemType)
    }

    private var colorForType: Color {
        switch action.vscodeItemType {
        case .project: .blue
        case .file: .secondary
        case .remote: .orange
        case nil: .secondary
        }
    }

    @ViewBuilder
    private func typeIndicator(_ type: VSCodeItemType) -> some View {
        switch type {
        case .remote:
            Image(systemName: "network")
                .font(.caption)
                .foregroundStyle(.orange)
        case .file:
            Image(systemName: "doc")
                .font(.caption)
                .foregroundStyle(.quaternary)
        case .project:
            EmptyView()
        }
    }
}

struct VSCodeActionPreviewView: View {
    let action: VSCodeAction

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

            if let path = action.projectPath {
                Text(abbreviatePath(path))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }

            if let variant = action.variant {
                Text(variant)
                    .font(.caption)
                    .foregroundStyle(.quaternary)
            }

            Text("Module: vscode")
                .font(.caption)
                .foregroundStyle(.quaternary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewIcon: String {
        action.iconName ?? typeIcon(action.vscodeItemType)
    }

    private var previewColor: Color {
        switch action.vscodeItemType {
        case .project: .blue
        case .file: .secondary
        case .remote: .orange
        case nil: .secondary
        }
    }
}

// MARK: - Helpers

private func typeIcon(_ type: VSCodeItemType?) -> String {
    switch type {
    case .project: "folder.badge.gearshape"
    case .file: "doc"
    case .remote: "network"
    case nil: "chevron.left.forwardslash.chevron.right"
    }
}

private func abbreviatePath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if path.hasPrefix(home) {
        return "~" + path.dropFirst(home.count)
    }
    return path
}
