import SwiftUI

struct SettingsActionListItemView: View {
    let action: SettingsAction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.iconName ?? "gearshape.2")
                .font(.title3)
                .foregroundStyle(.secondary)
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
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

struct SettingsActionPreviewView: View {
    let action: SettingsAction

    var body: some View {
        PreviewLayout(moduleName: "settings") {
            PreviewHeader(
                title: action.title,
                subtitle: action.subtitle,
                systemIcon: action.iconName ?? "gearshape.2"
            )
        }
    }
}
