import SwiftUI

struct BrowserActionListItemView: View {
    let action: BrowserAction

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
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

struct BrowserActionPreviewView: View {
    let action: BrowserAction

    private var faviconURL: URL? {
        guard let tabURL = action.tabURL,
              let url = URL(string: tabURL),
              let host = url.host
        else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=128")
    }

    private var domain: String? {
        guard let tabURL = action.tabURL,
              let url = URL(string: tabURL)
        else { return nil }
        return url.host
    }

    var body: some View {
        PreviewLayout(moduleName: "browser") {
            PreviewHeader(title: action.title, subtitle: action.subtitle) {
                heroSection
            }

            if let tabURL = action.tabURL {
                Divider()
                urlSection(tabURL)
            }

            if let bundleID = action.browserBundleID {
                browserRow(bundleID: bundleID)
            }
        }
    }

    @ViewBuilder
    private var heroSection: some View {
        if let faviconURL {
            HStack(spacing: 12) {
                AsyncImage(url: faviconURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fit)
                    default:
                        browserOrGlobeIcon
                    }
                }
                .frame(width: 48, height: 48)
                .cornerRadius(6)

                if let domain {
                    Text(domain)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer()
            }
        } else {
            Group {
                if let icon = action.browserIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: action.iconName ?? "globe")
                        .font(.system(size: 56))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 72, height: 72)
        }
    }

    private var browserOrGlobeIcon: some View {
        Group {
            if let icon = action.browserIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func urlSection(_ urlString: String) -> some View {
        Text(urlString)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .lineLimit(2)
            .textSelection(.enabled)
    }

    @ViewBuilder
    private func browserRow(bundleID: String) -> some View {
        HStack(spacing: 8) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 18, height: 18)
            }
            Text(BrowserRegistry.name(for: bundleID) ?? bundleID)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
