import SwiftUI

struct ApplicationActionListItemView: View {
    let action: ApplicationAction

    var body: some View {
        HStack(spacing: 12) {
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

struct ApplicationActionPreviewView: View {
    let action: ApplicationAction

    var body: some View {
        PreviewLayout(moduleName: "application") {
            PreviewHeader(title: action.title, subtitle: action.subtitle) {
                Group {
                    if let icon = action.appIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: action.iconName ?? "app")
                            .font(.system(size: 56))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 72, height: 72)
            }
        }
    }
}
