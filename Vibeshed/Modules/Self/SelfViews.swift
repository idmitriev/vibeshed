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
        VStack(spacing: 12) {
            Image(systemName: action.iconName ?? "sparkle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .frame(width: 64, height: 64)

            Text(action.title)
                .font(.title2)

            Text(action.subtitle)
                .font(.body)
                .foregroundStyle(.secondary)

            Text("Module: vibeshed")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
