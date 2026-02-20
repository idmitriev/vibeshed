import SwiftUI

struct SelfActionListItemView: View {
    let action: SelfAction

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.iconName ?? "sparkle")
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

struct SelfActionPreviewView: View {
    let action: SelfAction

    var body: some View {
        PreviewLayout(moduleName: "vibeshed") {
            PreviewHeader(
                title: action.title,
                subtitle: action.subtitle,
                systemIcon: action.iconName ?? "sparkle"
            )
        }
    }
}
