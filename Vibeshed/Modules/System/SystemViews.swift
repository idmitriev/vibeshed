import SwiftUI

struct SystemActionListItemView: View {
    let action: SystemAction

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.iconName ?? "gearshape")
                .font(.title3)
                .foregroundStyle(.secondary)
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
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct SystemActionPreviewView: View {
    let action: SystemAction

    var body: some View {
        PreviewLayout(moduleName: "system") {
            PreviewHeader(
                title: action.title,
                subtitle: action.subtitle,
                systemIcon: action.iconName ?? "gearshape"
            )
        }
    }
}
