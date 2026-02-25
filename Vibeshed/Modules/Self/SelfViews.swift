import SwiftUI

struct SelfActionListItemView: View {
    let action: SelfAction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.iconName ?? "sparkle")
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
