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
    @State private var screenshot: NSImage?

    var body: some View {
        PreviewLayout(moduleName: "window") {
            if let screenshot {
                screenshotHero(screenshot)
            } else if action.windowID != nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
            } else {
                iconHero
            }

            Text(action.title)
                .font(.title3)
                .fontWeight(.medium)
                .lineLimit(2)

            Text(action.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            if let bundleID = action.appBundleID {
                appInfoRow(bundleID: bundleID)
            }
        }
        .task(id: action.windowID) {
            guard let wid = action.windowID else { return }
            screenshot = captureWindow(wid)
        }
    }

    @ViewBuilder
    private func screenshotHero(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.tertiary, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }

    private var iconHero: some View {
        Image(systemName: action.iconName ?? "macwindow")
            .font(.system(size: 48))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
    }

    @ViewBuilder
    private func appInfoRow(bundleID: String) -> some View {
        HStack(spacing: 8) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 20, height: 20)
            }
            Text(bundleID)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    private func captureWindow(_ windowID: Int) -> NSImage? {
        guard let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            CGWindowID(windowID),
            [.bestResolution, .boundsIgnoreFraming]
        ) else { return nil }
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width / 2, height: cgImage.height / 2)
        )
    }
}
