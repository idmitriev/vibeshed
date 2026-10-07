import Foundation

/// How a downloaded image covers the screen.
enum WallpaperScaling: String, CaseIterable, Sendable {
    /// Photos fill the screen; artwork is fitted on a matte unless its shape is close to the screen's.
    case auto
    /// Fill the screen, cropping what doesn't fit.
    case fill
    /// Show the whole image on a matte in its edge color.
    case fit
}

struct WallpaperConfig: Codable, Sendable, Equatable {
    /// Sources to search, in the order "Search Wallpapers" mixes their results:
    /// wallhaven, unsplash, artic, rijksmuseum, met. Unsplash is skipped without a key.
    var sources: [String] = WallpaperSourceID.allCases.map(\.rawValue)

    /// Results per source in a search (1–30).
    var maxResultsPerSource: Int = 10

    /// landscape, portrait or any. Wallhaven and Unsplash filter by it; the museums list
    /// matching artworks first.
    var orientation: String = WallpaperOrientation.landscape.rawValue

    /// auto, fill or fit (see `WallpaperScaling`).
    var scaling: String = WallpaperScaling.auto.rawValue

    /// Where downloaded wallpapers go (`~` allowed); files there are never deleted. Unset,
    /// they go to Application Support, which keeps the 40 most recent.
    var downloadDirectory: String?

    /// Optional; sent with Wallhaven requests.
    var wallhavenAPIKey: String?

    /// Wallhaven categories to search: general, anime, people.
    var wallhavenCategories: [String] = ["general", "anime"]

    /// Access key of an Unsplash app (https://unsplash.com/oauth/applications).
    var unsplashAccessKey: String?

    /// Action names to offer (nil = all). Families work too: `search`, `random`.
    var enabledActions: Set<String>?
}

extension WallpaperConfig {
    /// Every key is optional: a missing one keeps its default above instead of failing
    /// the whole section (see `ApplicationConfig`).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        sources = try container.decodeIfPresent([String].self, forKey: .sources) ?? defaults.sources
        maxResultsPerSource = try container.decodeIfPresent(Int.self, forKey: .maxResultsPerSource)
            ?? defaults.maxResultsPerSource
        orientation = try container.decodeIfPresent(String.self, forKey: .orientation) ?? defaults.orientation
        scaling = try container.decodeIfPresent(String.self, forKey: .scaling) ?? defaults.scaling
        downloadDirectory = try container.decodeIfPresent(String.self, forKey: .downloadDirectory)
        wallhavenAPIKey = try container.decodeIfPresent(String.self, forKey: .wallhavenAPIKey)
        wallhavenCategories = try container.decodeIfPresent([String].self, forKey: .wallhavenCategories)
            ?? defaults.wallhavenCategories
        unsplashAccessKey = try container.decodeIfPresent(String.self, forKey: .unsplashAccessKey)
        enabledActions = try container.decodeIfPresent(Set<String>.self, forKey: .enabledActions)
    }

    /// The configured sources that can run: Unsplash only with an access key.
    var activeSources: [WallpaperSourceID] {
        sources.compactMap(WallpaperSourceID.init(rawValue:)).filter { source in
            source != .unsplash || unsplashAccessKey?.isEmpty == false
        }
    }

    var searchOptions: WallpaperSearchOptions {
        WallpaperSearchOptions(
            limit: maxResultsPerSource,
            orientation: WallpaperOrientation(rawValue: orientation) ?? .landscape
        )
    }

    var resolvedScaling: WallpaperScaling {
        WallpaperScaling(rawValue: scaling) ?? .auto
    }

    func validationErrors() -> [String] {
        var errors: [String] = []
        let known = WallpaperSourceID.allCases.map(\.rawValue)
        for source in sources where !known.contains(source) {
            errors.append("Unknown source '\(source)'. Valid: \(known.joined(separator: ", "))")
        }
        if Set(sources).count < sources.count {
            errors.append("sources lists a source twice")
        }
        if !(1 ... 30).contains(maxResultsPerSource) {
            errors.append("maxResultsPerSource must be between 1 and 30")
        }
        if WallpaperOrientation(rawValue: orientation) == nil {
            errors.append("orientation must be one of: landscape, portrait, any")
        }
        if WallpaperScaling(rawValue: scaling) == nil {
            errors.append("scaling must be one of: auto, fill, fit")
        }
        let categories = ["general", "anime", "people"]
        for category in wallhavenCategories where !categories.contains(category.lowercased()) {
            errors.append("Unknown Wallhaven category '\(category)'. Valid: \(categories.joined(separator: ", "))")
        }
        for (name, value) in [("wallhavenAPIKey", wallhavenAPIKey), ("unsplashAccessKey", unsplashAccessKey)] {
            if let value, value.trimmingCharacters(in: .whitespaces).isEmpty {
                errors.append("\(name) must not be empty when set")
            }
        }
        if let downloadDirectory, downloadDirectory.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("downloadDirectory must not be empty when set")
        }
        return errors
    }
}
