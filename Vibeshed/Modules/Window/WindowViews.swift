import SwiftUI

struct WindowActionListItemView: View {
    let action: WindowAction

    private var appIcon: NSImage? {
        guard let path = action.appIconPath else { return nil }
        return NSWorkspace.shared.icon(forFile: path)
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: action.iconName ?? "macwindow")
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

struct WindowActionPreviewView: View {
    let action: WindowAction
    @State private var screenshot: NSImage?

    var body: some View {
        PreviewLayout(moduleName: "window") {
            PreviewHeader(title: action.title, subtitle: action.subtitle) {
                if let screenshot {
                    screenshotHero(screenshot)
                } else if action.windowID != nil {
                    ProgressView()
                        .frame(height: 160)
                } else {
                    Image(systemName: action.iconName ?? "macwindow")
                        .font(.system(size: 56))
                        .foregroundStyle(.secondary)
                        .frame(width: 72, height: 72)
                }
            }

            if let bundleID = action.appBundleID {
                appInfoRow(bundleID: bundleID)
            }
        }
        .task(id: action.windowID) {
            guard let wid = action.windowID else { return }
            screenshot = captureWindow(wid)
        }
    }

    private func screenshotHero(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.tertiary, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }

    private func appInfoRow(bundleID: String) -> some View {
        HStack(spacing: 8) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 22, height: 22)
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
