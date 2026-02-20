import SwiftUI

struct SpotifyActionListItemView: View {
    let action: SpotifyAction

    var body: some View {
        HStack(spacing: 10) {
            artworkOrIcon
                .frame(width: 28, height: 28)
                .cornerRadius(4)
                .clipped()

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

            if let itemType = action.spotifyItemType,
               itemType != .control {
                Text(itemType.rawValue.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var artworkOrIcon: some View {
        if let artworkURL = action.artworkURL,
           let url = URL(string: artworkURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    fallbackIcon
                }
            }
        } else {
            fallbackIcon
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: action.iconName ?? "music.note")
            .font(.title3)
            .foregroundStyle(.secondary)
    }
}

struct SpotifyActionPreviewView: View {
    let action: SpotifyAction

    var body: some View {
        PreviewLayout(moduleName: "spotify") {
            PreviewHeader(title: action.title, subtitle: action.subtitle) {
                artworkHero
            }

            HStack(spacing: 8) {
                if let itemType = action.spotifyItemType {
                    PreviewPill(
                        text: itemType.rawValue.capitalized,
                        icon: iconForType(itemType),
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
        }
    }

    @ViewBuilder
    private var artworkHero: some View {
        if let artworkURL = action.artworkURL,
           let url = URL(string: artworkURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(8)
                default:
                    previewFallbackIcon
                }
            }
            .frame(maxHeight: 200)
        } else {
            previewFallbackIcon
        }
    }

    private var previewFallbackIcon: some View {
        Image(systemName: action.iconName ?? "music.note")
            .font(.system(size: 48))
            .foregroundStyle(.secondary)
            .frame(width: 64, height: 64)
    }

    private func formatDuration(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private func iconForType(_ type: SpotifyItemType) -> String {
    switch type {
    case .track: "music.note"
    case .album: "square.stack"
    case .artist: "person"
    case .playlist: "music.note.list"
    case .nowPlaying: "waveform"
    case .control: "playpause"
    }
}
