import SwiftUI

struct ApplicationActionListItemView: View {
    let action: ApplicationAction

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let icon = action.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: action.iconName ?? "app")
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

struct ApplicationActionPreviewView: View {
    let action: ApplicationAction

    var body: some View {
        PreviewLayout(moduleName: "application") {
            Group {
                if let icon = action.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: action.iconName ?? "app")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 80, height: 80)
            .frame(maxWidth: .infinity)

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
