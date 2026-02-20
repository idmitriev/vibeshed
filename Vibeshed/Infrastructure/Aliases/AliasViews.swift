import SwiftUI

struct AliasActionListItemView: View {
    let action: AliasAction

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.iconName ?? "star.fill")
                .font(.title3)
                .foregroundStyle(.yellow)
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

struct AliasActionPreviewView: View {
    let action: AliasAction

    var body: some View {
        PreviewLayout(moduleName: "alias") {
            Image(systemName: action.iconName ?? "star.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)
                .frame(maxWidth: .infinity)
                .frame(height: 56)

            Text(action.title)
                .font(.title3)
                .fontWeight(.medium)
                .lineLimit(2)

            Text(action.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }
}
