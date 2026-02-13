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
        VStack(spacing: 12) {
            previewArtworkOrIcon
                .frame(width: 64, height: 64)
                .cornerRadius(8)
                .clipped()

            Text(action.title)
                .font(.title2)

            Text(action.subtitle)
                .font(.body)
                .foregroundStyle(.secondary)

            if let itemType = action.spotifyItemType {
                Label(itemType.rawValue.capitalized, systemImage: iconForType(itemType))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text("Module: spotify")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var previewArtworkOrIcon: some View {
        if let artworkURL = action.artworkURL,
           let url = URL(string: artworkURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    previewFallbackIcon
                }
            }
        } else {
            previewFallbackIcon
        }
    }

    private var previewFallbackIcon: some View {
        Image(systemName: action.iconName ?? "music.note")
            .font(.largeTitle)
            .foregroundStyle(.secondary)
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
