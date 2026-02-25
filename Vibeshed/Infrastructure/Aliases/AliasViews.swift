import SwiftUI

struct AliasActionListItemView: View {
    let action: AliasAction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.iconName ?? "star.fill")
                .font(.title3)
                .foregroundStyle(.yellow)
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

struct AliasActionPreviewView: View {
    let action: AliasAction

    var body: some View {
        PreviewLayout(moduleName: "alias") {
            PreviewHeader(
                title: action.title,
                subtitle: action.subtitle,
                systemIcon: action.iconName ?? "star.fill",
                iconColor: .yellow
            )
        }
    }
}
