import SwiftUI

extension ProjectAccent {
    var color: Color {
        switch self {
        case .blue: .blue
        case .purple: .purple
        case .orange: .orange
        case .green: .green
        case .cyan: .cyan
        case .red: .red
        case .secondary: .secondary
        }
    }
}

struct RecentProjectListItemView: View {
    let item: RecentProjectItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.listIcon)
                .font(.title3)
                .foregroundStyle(item.accent.color)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                    .lineLimit(1)

                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 4) {
                if item.isOpen {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                }
                if let trailingIcon = item.trailingIcon {
                    Image(systemName: trailingIcon)
                        .font(.caption)
                        .foregroundStyle(item.trailingIconAccent.color)
                }
                if let trailingLabel = item.trailingLabel {
                    Text(trailingLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

struct RecentProjectPreviewView: View {
    let item: RecentProjectItem
    let moduleID: String

    var body: some View {
        PreviewLayout(moduleName: moduleID) {
            PreviewHeader(
                title: item.title,
                subtitle: item.subtitle,
                systemIcon: item.listIcon,
                iconColor: item.accent.color
            )

            ForEach(Array(item.previewRows.enumerated()), id: \.offset) { _, row in
                metadataRow(row)
            }

            HStack(spacing: 8) {
                ForEach(Array(item.previewPills.enumerated()), id: \.offset) { _, pill in
                    PreviewPill(text: pill.text, icon: pill.icon, color: pill.accent.color)
                }
                if item.isOpen {
                    PreviewPill(text: "Open", icon: "circle.fill", color: .green)
                }
            }
        }
    }

    @ViewBuilder
    private func metadataRow(_ row: ProjectMetaRow) -> some View {
        let view = PreviewMetadataRow(icon: row.icon, label: row.label, value: row.value)
        if row.selectable {
            view.textSelection(.enabled)
        } else {
            view
        }
    }
}
