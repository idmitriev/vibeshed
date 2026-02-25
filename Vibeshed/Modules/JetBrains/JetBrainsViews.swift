import SwiftUI

struct JetBrainsActionListItemView: View {
    let action: JetBrainsAction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.iconName ?? "hammer")
                .font(.title3)
                .foregroundStyle(colorForIDE)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.body)
                    .lineLimit(1)

                if !action.subtitle.isEmpty {
                    Text(action.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 4) {
                if action.isOpen {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                }
                if let ideName = action.ideName {
                    Text(ideName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var colorForIDE: Color {
        switch action.ideTag {
        case "idea": .purple
        case "pycharm": .green
        case "webstorm": .cyan
        case "datagrip": .purple
        case "goland": .blue
        case "rustrover": .orange
        case "clion": .green
        case "rider": .blue
        case "phpstorm": .purple
        case "rubymine": .red
        case "studio": .green
        default: .secondary
        }
    }
}

struct JetBrainsActionPreviewView: View {
    let action: JetBrainsAction

    var body: some View {
        PreviewLayout(moduleName: "jetbrains") {
            PreviewHeader(
                title: action.title,
                subtitle: action.subtitle,
                systemIcon: action.iconName ?? "hammer",
                iconColor: previewColor
            )

            if let path = action.projectPath {
                PreviewMetadataRow(
                    icon: "folder",
                    label: "Path",
                    value: path
                )
                .textSelection(.enabled)
            }

            if let context = action.frameContext {
                PreviewMetadataRow(
                    icon: "doc.text",
                    label: "Last opened",
                    value: context
                )
            }

            HStack(spacing: 8) {
                if let ideName = action.ideName {
                    PreviewPill(
                        text: ideName,
                        icon: action.iconName ?? "hammer",
                        color: previewColor
                    )
                }
                if action.isOpen {
                    PreviewPill(
                        text: "Open",
                        icon: "circle.fill",
                        color: .green
                    )
                }
            }
        }
    }

    private var previewColor: Color {
        switch action.ideTag {
        case "idea": .purple
        case "pycharm": .green
        case "webstorm": .cyan
        case "datagrip": .purple
        case "goland": .blue
        case "rustrover": .orange
        case "clion": .green
        case "rider": .blue
        case "phpstorm": .purple
        case "rubymine": .red
        case "studio": .green
        default: .secondary
        }
    }
}
