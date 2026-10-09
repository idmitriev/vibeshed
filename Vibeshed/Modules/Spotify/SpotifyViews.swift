import SwiftUI

struct SpotifyActionListItemView: View {
    let action: SpotifyAction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.iconName ?? "music.note")
                .font(.title3)
                .foregroundStyle(.green)
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

            if let itemType = action.spotifyItemType,
               itemType != .control
            {
                Text(itemType.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

struct SpotifyActionPreviewView: View {
    let action: SpotifyAction

    var body: some View {
        PreviewLayout(moduleName: "spotify") {
            PreviewHeader(
                title: action.title,
                subtitle: action.subtitle,
                systemIcon: action.iconName ?? "music.note",
                iconColor: .green
            )

            HStack(spacing: 8) {
                if let itemType = action.spotifyItemType {
                    PreviewPill(
                        text: itemType.rawValue.capitalized,
                        icon: itemType.iconName,
                        color: .green
                    )
                }
                if let ms = action.durationMs, ms > 0 {
                    PreviewPill(
                        text: formatDuration(ms),
                        icon: "clock",
                        color: .secondary
                    )
                }
            }

            artworkSection
        }
    }

    @ViewBuilder
    private var artworkSection: some View {
        if let artworkURL = action.artworkURL,
           let url = URL(string: artworkURL)
        {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(8)
                default:
                    EmptyView()
                }
            }
            .frame(maxHeight: 220)
        }
    }

    private func formatDuration(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// The preview for a search result: its cover, large, over what it is and who made it.
struct SpotifySearchItemPreview: View {
    let item: SpotifySearchItem

    var body: some View {
        PreviewLayout(moduleName: "spotify") {
            PreviewHeader(title: item.name, subtitle: item.byline) {
                artwork
            }

            PreviewPill(text: item.kind.searchLabel, icon: item.kind.iconName, color: .green)
        }
    }

    /// The larger cover, with the list's thumbnail standing in while it loads.
    private var artwork: some View {
        AsyncImage(url: item.previewArtworkURL) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fit)
            } else {
                AsyncImage(url: item.artworkURL) { thumbnail in
                    if let image = thumbnail.image {
                        image.resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: item.kind.iconName)
                            .font(.system(size: 56))
                            .foregroundStyle(.green)
                            .frame(width: 72, height: 72)
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        // Spotify shows artists round and everything else square.
        .clipShape(item.kind == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 8)))
        .frame(maxWidth: 220, maxHeight: 220)
    }
}
