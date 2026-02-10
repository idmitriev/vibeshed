import SwiftUI

struct WindowActionListItemView: View {
    let action: WindowAction

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.iconName ?? "macwindow")
                .font(.title3)
                .frame(width: 28, height: 28)
                .foregroundStyle(.secondary)

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

struct WindowActionPreviewView: View {
    let action: WindowAction

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: action.iconName ?? "macwindow")
                .font(.largeTitle)

            Text(action.title)
                .font(.title2)

            Text(action.subtitle)
                .font(.body)
                .foregroundStyle(.secondary)

            Text("Module: window")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
