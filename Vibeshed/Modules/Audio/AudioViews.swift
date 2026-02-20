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
        PreviewLayout(moduleName: "audio") {
            Image(systemName: action.iconName ?? "speaker.wave.2")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
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
