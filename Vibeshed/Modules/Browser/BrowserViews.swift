import SwiftUI

struct BrowserActionListItemView: View {
    let action: BrowserAction

    var body: some View {
        HStack(spacing: 10) {
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

struct BrowserActionPreviewView: View {
    let action: BrowserAction

    var body: some View {
        VStack(spacing: 12) {
            Group {
                if let icon = action.browserIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: action.iconName ?? "globe")
                        .font(.largeTitle)
                }
            }
            .frame(width: 64, height: 64)

            Text(action.title)
                .font(.title2)

            Text(action.subtitle)
                .font(.body)
                .foregroundStyle(.secondary)

            Text("Module: browser")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
