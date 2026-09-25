import SwiftUI

struct ThemeAction: Action {
    let id: ActionID
    let title: String
    let subtitle: String
    let iconName: String?
    let relevanceScore: Double
    let keywords: [String]
    let parameters: [ActionParameter]
    /// Set for `apply.<slug>` actions: drives the palette preview.
    let theme: ResolvedTheme?
    let wallpaper: ThemeWallpaperPreview?

    private let runner: @Sendable (ParameterValues) async throws -> ActionResult

    init(
        id: ActionID,
        title: String,
        subtitle: String,
        iconName: String? = nil,
        relevanceScore: Double = 0.8,
        keywords: [String] = [],
        parameters: [ActionParameter] = [],
        theme: ResolvedTheme? = nil,
        wallpaper: ThemeWallpaperPreview? = nil,
        runner: @escaping @Sendable (ParameterValues) async throws -> ActionResult
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.relevanceScore = relevanceScore
        self.keywords = keywords
        self.parameters = parameters
        self.theme = theme
        self.wallpaper = wallpaper
        self.runner = runner
    }

    func run(with values: ParameterValues) async throws -> ActionResult {
        try await runner(values)
    }

    @MainActor
    func makePreviewView() -> AnyView? {
        guard let theme else { return nil }
        return AnyView(ThemePreviewView(theme: theme, wallpaper: wallpaper))
    }
}
