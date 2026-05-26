import SwiftUI

struct ZedActionListItemView: View {
    let action: ZedAction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.isRemote ? "network" : "folder")
                .font(.title3)
                .foregroundStyle(action.isRemote ? .orange : .purple)
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
                if action.isRemote {
                    Image(systemName: "network")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("Zed")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

struct ZedActionPreviewView: View {
    let action: ZedAction

    var body: some View {
        PreviewLayout(moduleName: "zed") {
            PreviewHeader(
                title: action.title,
                subtitle: action.subtitle,
                systemIcon: action.isRemote ? "network" : "folder",
                iconColor: action.isRemote ? .orange : .purple
            )

            if let path = action.projectPath {
                PreviewMetadataRow(
                    icon: "folder",
                    label: "Path",
                    value: abbreviatePath(path)
                )
                .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                PreviewPill(
                    text: action.isRemote ? "Remote" : "Project",
                    icon: action.isRemote ? "network" : "folder",
                    color: action.isRemote ? .orange : .purple
                )
                if let host = action.remoteHost {
                    PreviewPill(text: host, color: .secondary)
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
}

private func abbreviatePath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if path.hasPrefix(home) {
        return "~" + path.dropFirst(home.count)
    }
    return path
}
