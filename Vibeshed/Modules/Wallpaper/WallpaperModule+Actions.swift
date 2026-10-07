import Foundation

/// `search` and `random` across the active sources, `search.<source>` and
/// `random.<source>` for each one (when there's more than one), and `openSourcePage`.
extension WallpaperModule {
    func buildActions() -> [WallpaperAction] {
        let active = config.activeSources
        guard !active.isEmpty else { return [openSourcePageAction()] }
        var actions = [searchAction(active)]
        if active.count > 1 {
            actions += active.map(searchAction)
        }
        actions.append(randomAction(active))
        if active.count > 1 {
            actions += active.map(randomAction)
        }
        actions.append(openSourcePageAction())
        return actions
    }

    private static let keywords = ["wallpaper", "background", "desktop", "picture", "image"]

    private static var wallpaperParameter: ActionParameter {
        ActionParameter(
            id: parameterID,
            label: "Wallpaper",
            type: .dynamicSelection(hint: "wallpapers"),
            isRequired: true,
            rankedByModule: true
        )
    }

    private func searchAction(_ sources: [WallpaperSourceID]) -> WallpaperAction {
        WallpaperAction(
            id: ActionID(module: id, name: "search"),
            title: "Search Wallpapers",
            subtitle: "Find one on \(ListFormatter.localizedString(byJoining: sources.map(\.displayName))) and set it",
            iconName: "photo.on.rectangle.angled",
            relevanceScore: 0.85,
            keywords: Self.keywords + ["search", "find", "online", "photo", "art"],
            parameters: [Self.wallpaperParameter]
        ) { values in
            guard let optionID = values[Self.parameterID] else { return .keepOpen }
            return try await self.setWallpaper(optionID: optionID)
        }
    }

    private func searchAction(_ source: WallpaperSourceID) -> WallpaperAction {
        WallpaperAction(
            id: ActionID(module: id, name: "search.\(source.rawValue)"),
            title: "Search \(source.displayName)",
            subtitle: Self.summary(of: source),
            iconName: source.iconName,
            relevanceScore: 0.75,
            keywords: Self.keywords + ["search", "find"] + Self.keywords(for: source),
            parameters: [Self.wallpaperParameter]
        ) { values in
            guard let optionID = values[Self.parameterID] else { return .keepOpen }
            return try await self.setWallpaper(optionID: optionID)
        }
    }

    private func randomAction(_ sources: [WallpaperSourceID]) -> WallpaperAction {
        WallpaperAction(
            id: ActionID(module: id, name: "random"),
            title: "Random Wallpaper",
            subtitle: "A featured image from \(ListFormatter.localizedString(byJoining: sources.map(\.displayName)))",
            iconName: "shuffle",
            relevanceScore: 0.7,
            keywords: Self.keywords + ["random", "shuffle", "surprise", "new"]
        ) { _ in
            try await self.setRandomWallpaper(from: sources)
        }
    }

    private func randomAction(_ source: WallpaperSourceID) -> WallpaperAction {
        WallpaperAction(
            id: ActionID(module: id, name: "random.\(source.rawValue)"),
            title: "Random Wallpaper from \(source.displayName)",
            subtitle: Self.featured(from: source),
            iconName: "shuffle",
            relevanceScore: 0.6,
            keywords: Self.keywords + ["random", "shuffle"] + Self.keywords(for: source)
        ) { _ in
            try await self.setRandomWallpaper(from: [source])
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

    private static func summary(of source: WallpaperSourceID) -> String {
        switch source {
        case .wallhaven: "Wallpapers uploaded to wallhaven.cc"
        case .unsplash: "Free-to-use photos"
        case .artic: "Public-domain artworks in Chicago"
        case .rijksmuseum: "Public-domain paintings, prints and drawings in Amsterdam"
        case .met: "Public-domain paintings in New York"
        }
    }

    private static func featured(from source: WallpaperSourceID) -> String {
        switch source {
        case .wallhaven: "From the past year's top list"
        case .unsplash: "From Unsplash's Wallpapers topic"
        case .artic: "One of the museum's highlighted paintings"
        case .rijksmuseum: "One of the museum's landscape paintings"
        case .met: "One of the museum's highlighted paintings"
        }
    }

    private static func keywords(for source: WallpaperSourceID) -> [String] {
        let name = titleKeywords(source.displayName)
        switch source {
        case .wallhaven: return name
        case .unsplash: return name + ["photo", "photography"]
        case .artic: return name + ["aic", "museum", "art", "painting"]
        case .rijksmuseum: return name + ["museum", "art", "painting", "amsterdam"]
        case .met: return name + ["metropolitan", "museum", "art", "painting"]
        }
    }
}
