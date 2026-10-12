import SwiftUI

/// Preview for a search result: the image, who made it, and on what terms.
struct OnlineWallpaperPreview: View {
    let wallpaper: OnlineWallpaper

    var body: some View {
        PreviewLayout(moduleName: "wallpaper") {
            PreviewHeader(title: wallpaper.title, subtitle: byline) {
                image
            }

            VStack(alignment: .leading, spacing: 6) {
                PreviewMetadataRow(
                    icon: wallpaper.source.iconName, label: "Source", value: wallpaper.source.displayName
                )
                if let date = wallpaper.date {
                    PreviewMetadataRow(icon: "calendar", label: "Date", value: date)
                }
                if let detail = wallpaper.detail {
                    PreviewMetadataRow(icon: "paintbrush", label: "Details", value: detail)
                }
                // Wallhaven search results are titled by their size already.
                if let resolution = wallpaper.resolution, resolution != wallpaper.title {
                    PreviewMetadataRow(icon: "aspectratio", label: "Size", value: resolution)
                }
                if let license = wallpaper.license {
                    PreviewMetadataRow(icon: "checkmark.seal", label: "License", value: license)
                }
            }

            if wallpaper.colors.count > 1 {
                SwatchStrip(colors: wallpaper.colors.compactMap { ThemeColor(hex: $0)?.color }, size: 18)
            }
        }
    }

    /// Unsplash asks for "Photo by <name> on Unsplash".
    private var byline: String {
        guard let credit = wallpaper.credit else { return "" }
        return wallpaper.source == .unsplash ? "Photo by \(credit) on Unsplash" : credit
    }

    /// The preview-size image, with the list's thumbnail standing in while it loads.
    private var image: some View {
        AsyncImage(url: wallpaper.previewURL) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fit)
            } else {
                AsyncImage(url: wallpaper.thumbnailURL) { thumbnail in
                    if let image = thumbnail.image {
                        image.resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: phase.error == nil ? "photo" : "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 200)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
