import SwiftUI

enum SpotifyItemType: String, Sendable {
    case track
    case album
    case artist
    case playlist
    case nowPlaying
    case control
}

struct SpotifyAction: Action {
    let id: ActionID
    let title: String
    let subtitle: String
    let iconName: String?
    let relevanceScore: Double
    let keywords: [String]
    let parameters: [ActionParameter]

    let artworkURL: String?
    let spotifyItemType: SpotifyItemType?
    let durationMs: Int?

    private let runner: @Sendable ([String: Any]) async throws -> ActionResult

    init(
        id: ActionID,
        title: String,
        subtitle: String,
        iconName: String? = nil,
        relevanceScore: Double = 0.8,
        keywords: [String] = [],
        parameters: [ActionParameter] = [],
        artworkURL: String? = nil,
        spotifyItemType: SpotifyItemType? = nil,
        durationMs: Int? = nil,
        runner: @escaping @Sendable ([String: Any]) async throws -> ActionResult
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.relevanceScore = relevanceScore
        self.keywords = keywords
        self.parameters = parameters
        self.artworkURL = artworkURL
        self.spotifyItemType = spotifyItemType
        self.durationMs = durationMs
        self.runner = runner
    }

    func run(with values: [String: Any]) async throws -> ActionResult {
        try await runner(values)
    }

    @MainActor
    func makeListItemView() -> AnyView? {
        AnyView(SpotifyActionListItemView(action: self))
    }

    @MainActor
    func makePreviewView() -> AnyView? {
        AnyView(SpotifyActionPreviewView(action: self))
    }
}
