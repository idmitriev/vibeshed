import Foundation

/// Search Wallpapers and Random Wallpaper, each asking for a source first (when more
/// than one is active), and Open Wallpaper Source Page.
extension WallpaperModule {
    func buildActions() -> [WallpaperAction] {
        let active = config.activeSources
        guard !active.isEmpty else { return [openSourcePageAction()] }
        return [searchAction(active), randomAction(active), openSourcePageAction()]
    }

    private static let keywords = ["wallpaper", "background", "desktop", "picture", "image"]

    private func searchAction(_ sources: [WallpaperSourceID]) -> WallpaperAction {
        let results = ActionParameter(
            id: Self.wallpaperParameterID,
            label: "Wallpaper",
            type: .dynamicSelection(hint: "wallpapers"),
            isRequired: true,
            rankedByModule: true
        )
        return WallpaperAction(
            id: ActionID(module: id, name: "search"),
            title: "Search Wallpapers",
            subtitle: "Find one on \(Self.names(sources)) and set it",
            iconName: "photo.on.rectangle.angled",
            relevanceScore: 0.85,
            keywords: Self.keywords + ["search", "find", "online", "photo", "art", "painting", "museum"]
                + sources.flatMap(Self.keywords(for:)),
            parameters: sourceParameter(sources, featured: false) + [results]
        ) { values in
            guard let optionID = values[Self.wallpaperParameterID] else { return .keepOpen }
            return try await self.setWallpaper(optionID: optionID)
        }
    }

    private func randomAction(_ sources: [WallpaperSourceID]) -> WallpaperAction {
        let subject = ActionParameter(
            id: Self.queryParameterID,
            label: "Subject",
            type: .dynamicSelection(hint: "a subject, or nothing for any"),
            isRequired: true,
            rankedByModule: true
        )
        return WallpaperAction(
            id: ActionID(module: id, name: "random"),
            title: "Random Wallpaper",
            subtitle: "A random image from \(Self.names(sources)), on any subject or one you type",
            iconName: "shuffle",
            relevanceScore: 0.7,
            keywords: Self.keywords + ["random", "shuffle", "surprise", "new"],
            parameters: sourceParameter(sources, featured: true) + [subject]
        ) { values in
            try await self.setRandomWallpaper(
                source: values[Self.sourceParameterID], query: values[Self.queryParameterID]
            )
        }
    }

    private func openSourcePageAction() -> WallpaperAction {
        WallpaperAction(
            id: ActionID(module: id, name: "openSourcePage"),
            title: "Open Wallpaper Source Page",
            subtitle: "The web page the current wallpaper was downloaded from",
            iconName: "safari",
            relevanceScore: 0.65,
            keywords: Self.keywords + ["source", "page", "credit", "artist", "info", "open", "web"]
        ) { _ in
            await self.openSourcePage()
        }
    }

    /// The Source step: all sources first, then each. None with a single source.
    /// `featured` describes what a random pick draws on instead of what a search covers.
    private func sourceParameter(_ sources: [WallpaperSourceID], featured: Bool) -> [ActionParameter] {
        guard sources.count > 1 else { return [] }
        let all = ParameterOption(
            id: Self.allSources,
            label: "All Sources",
            subtitle: Self.names(sources),
            iconName: "square.stack"
        )
        let each = sources.map { source in
            ParameterOption(
                id: source.rawValue,
                label: source.displayName,
                subtitle: isBlocked(source)
                    ? "Turning away apps with a browser check right now"
                    : featured ? Self.featured(from: source) : Self.summary(of: source),
                iconName: source.iconName,
                keywords: Self.keywords(for: source)
            )
        }
        return [ActionParameter(
            id: Self.sourceParameterID, label: "Source", type: .selection([all] + each), isRequired: true
        )]
    }

    private static func names(_ sources: [WallpaperSourceID]) -> String {
        ListFormatter.localizedString(byJoining: sources.map(\.displayName))
    }

    private static func summary(of source: WallpaperSourceID) -> String {
        switch source {
        case .wallhaven: "Wallpapers uploaded to wallhaven.cc"
        case .unsplash: "Free-to-use photos"
        case .artic: "Public-domain artworks in Chicago"
        case .rijksmuseum: "Public-domain paintings, prints and drawings in Amsterdam"
        case .met: "Public-domain paintings in New York"
        }
    }

    /// What a random pick with no subject draws on.
    private static func featured(from source: WallpaperSourceID) -> String {
        switch source {
        case .wallhaven: "The past year's top list"
        case .unsplash: "Unsplash's Wallpapers topic"
        case .artic: "The museum's highlighted paintings"
        case .rijksmuseum: "The museum's landscape paintings"
        case .met: "The museum's highlighted paintings"
        }
    }

    static func keywords(for source: WallpaperSourceID) -> [String] {
        let name = titleKeywords(source.displayName)
        switch source {
        case .wallhaven: return name
        case .unsplash: return name + ["photo", "photography"]
        case .artic: return name + ["aic", "chicago"]
        case .rijksmuseum: return name + ["amsterdam"]
        case .met: return name + ["metropolitan", "new york"]
        }
    }
}
