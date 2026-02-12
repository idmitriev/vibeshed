import SwiftUI

struct AudioActionListItemView: View {
    let action: AudioAction

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.iconName ?? "speaker.wave.2")
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

struct AudioActionPreviewView: View {
    let action: AudioAction

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: action.iconName ?? "speaker.wave.2")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .frame(width: 64, height: 64)

            Text(action.title)
                .font(.title2)

            Text(action.subtitle)
                .font(.body)
                .foregroundStyle(.secondary)

            Text("Module: audio")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
