import SwiftUI

struct URLChooserListItemView: View {
    let action: URLChooserAction

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let icon = action.browserIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: action.iconName ?? "globe")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
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

            if action.profileDirectory != nil {
                Text("Profile")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.fill.opacity(0.3), in: Capsule())
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

struct URLChooserPreviewView: View {
    let action: URLChooserAction

    var body: some View {
        VStack(spacing: 12) {
            Group {
                if let icon = action.browserIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "globe")
                        .font(.largeTitle)
                }
            }
            .frame(width: 72, height: 72)

            Text(action.title)
                .font(.title2)

            Text(action.subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
