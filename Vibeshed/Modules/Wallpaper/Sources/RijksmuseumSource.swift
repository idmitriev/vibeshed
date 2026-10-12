import Foundation

/// The Rijksmuseum's data services (https://data.rijksmuseum.nl/docs/): no key. Search
/// returns only identifiers, so each hit is resolved in the Europeana profile
/// (`_profile=edm-framed` as JSON-LD), which carries the title, maker, rights and the IIIF image
/// (`iiif.micr.io`) in one response. There's no free-text search: a query is looked up
/// in titles, then descriptions. Only public-domain works are offered, and only flat
/// ones (paintings, prints, drawings, photographs), not boxes and cups.
struct RijksmuseumSource: WallpaperSource {
    let id = WallpaperSourceID.rijksmuseum
    var cache = ResolvedItemCache()

    private static let searchURL = URL(string: "https://data.rijksmuseum.nl/search/collection")!
    /// Landscape paintings: the featured selection and the pool for random picks.
    private static let featured = [
        URLQueryItem(name: "title", value: "landscape"),
        URLQueryItem(name: "type", value: "painting"),
    ]
    /// Object types (English labels) that hang flat on a wall.
    private static let flatTypes = [
        "painting", "print", "drawing", "photo", "watercolo", "scroll", "pastel", "gouache", "sketch", "map",
        "miniature",
    ]

    func search(_ query: String, options: WallpaperSearchOptions) async throws -> [OnlineWallpaper] {
        let identifiers: [String]
        if query.isEmpty {
            identifiers = try await search(Self.featured)
        } else {
            async let titles = search([URLQueryItem(name: "title", value: query)])
            async let descriptions = search([URLQueryItem(name: "description", value: query)])
            identifiers = try await Self.merged(titles, descriptions)
        }
        // Some hits drop out (in copyright, three-dimensional), so resolve a few extra.
        let resolved = try await resolve(Array(identifiers.prefix(options.limit * 2)))
        return Array(resolved.prefix(options.limit)).preferring(options.orientation)
    }

    func wallpaper(itemID: String) async throws -> OnlineWallpaper? {
        try await resolve(itemID)
    }

    /// From the landscape paintings, preferring the configured orientation.
    func random(options: WallpaperSearchOptions) async throws -> OnlineWallpaper? {
        let found = try await resolve(Array(search(Self.featured).shuffled().prefix(8)))
        return found.filter { options.orientation.matches($0.aspectRatio) }.randomElement() ?? found.randomElement()
    }

    /// Object IDs (`200108359`) for a search, in the API's order (up to 100).
    private func search(_ items: [URLQueryItem]) async throws -> [String] {
        let url = Self.searchURL.appending(queryItems: items + [URLQueryItem(name: "imageAvailable", value: "true")])
        return try await Self.parseSearch(WallpaperHTTP.json(url, source: id))
    }

    /// Wallpapers for `identifiers` in their order, skipping ones that don't qualify.
    private func resolve(_ identifiers: [String]) async throws -> [OnlineWallpaper] {
        try await WallpaperLookup.all(identifiers) { try await resolve($0) }
    }

    private func resolve(_ itemID: String) async throws -> OnlineWallpaper? {
        if let cached = await cache.lookup(itemID) { return cached }
        // The media type goes in the Accept header: a `+` in `_mediatype` reads as a space.
        guard let url = URL(string: "https://id.rijksmuseum.nl/\(itemID)?_profile=edm-framed") else { return nil }
        let json = try await WallpaperHTTP.json(url, source: id, headers: ["Accept": "application/ld+json"])
        let wallpaper = Self.wallpaper(json)
        await cache.store(wallpaper, for: itemID)
        return wallpaper
    }

    /// Title hits first, then description hits, each once.
    static func merged(_ first: [String], _ second: [String]) -> [String] {
        var seen = Set<String>()
        return (first + second).filter { seen.insert($0).inserted }
    }

    // MARK: - Parsing

    static func parseSearch(_ json: [String: Any]) -> [String] {
        (json["orderedItems"] as? [[String: Any]] ?? []).compactMap { item in
            WallpaperJSON.url(item["id"])?.lastPathComponent.nonEmpty
        }
    }

    /// A work from its `edm-framed` record; nil unless it's public domain, flat and has an image.
    static func wallpaper(_ json: [String: Any]) -> OnlineWallpaper? {
        guard let object = json["aggregatedCHO"] as? [String: Any],
              let itemID = WallpaperJSON.url(object["id"])?.lastPathComponent.nonEmpty,
              let rights = WallpaperJSON.string(json["edmRights"]), rights.contains("publicdomain"),
              let shownBy = json["isShownBy"] as? [String: Any],
              let service = imageService(shownBy)
        else { return nil }
        let types = LinkedData.labels(object["dcType"])
        guard types.isEmpty || types.contains(where: { type in flatTypes.contains { type.lowercased().contains($0) } })
        else { return nil }
        let creator = LinkedData.labels(object["creator"]).first
        return OnlineWallpaper(
            source: .rijksmuseum,
            sourceItemID: itemID,
            title: LinkedData.text(object["title"]) ?? "Untitled",
            credit: creator,
            creditURL: nil,
            date: LinkedData.text(object["created"]),
            detail: types.first.map { $0.prefix(1).uppercased() + $0.dropFirst() },
            pageURL: WallpaperJSON.url((json["isShownAt"] as? [String: Any])?["id"]),
            thumbnailURL: service.appendingPathComponent("full/200,/0/default.jpg"),
            previewURL: service.appendingPathComponent("full/!1200,1200/0/default.jpg"),
            image: .iiif(service),
            pixelWidth: nil,
            pixelHeight: nil,
            aspectRatio: LinkedData.text(object["extent"]).flatMap(aspectRatio(fromExtent:)),
            colors: [],
            license: rights.contains("zero") ? "Public domain (CC0)" : "Public domain",
            downloadTrackingURL: nil
        )
    }

    /// The IIIF service behind `isShownBy` (`https://iiif.micr.io/eBrWZ`).
    private static func imageService(_ shownBy: [String: Any]) -> URL? {
        let service = shownBy["http://rdfs.org/sioc/services#has_service"] as? [String: Any]
        if let url = WallpaperJSON.url(service?["id"]) { return url }
        guard let image = WallpaperJSON.string(shownBy["id"]), let range = image.range(of: "/full/") else {
            return nil
        }
        return URL(string: String(image[..<range.lowerBound]))
    }

    /// Width / height from "height 77 cm x width 63.5 cm x …" (the first of each).
    static func aspectRatio(fromExtent extent: String) -> Double? {
        func measure(_ name: String) -> Double? {
            guard let range = extent.range(of: name + " ") else { return nil }
            let number = extent[range.upperBound...].prefix { $0.isNumber || $0 == "." || $0 == "," }
            return Double(number.replacingOccurrences(of: ",", with: "."))
        }
        return WallpaperJSON.aspectRatio(width: measure("width"), height: measure("height"))
    }
}

/// Values in the Rijksmuseum's JSON-LD, which come as plain strings, language maps
/// (`{"en": …, "nl": …}`), `{"@language", "@value"}` objects, SKOS concepts with
/// `prefLabel`s, or arrays of any of these.
enum LinkedData {
    private static let prefLabel = "http://www.w3.org/2004/02/skos/core#prefLabel"
    private static let preferredLanguages = ["en", "nl"]

    /// The English text, else the Dutch, else any.
    static func text(_ value: Any?) -> String? {
        let values = tagged(value)
        for language in preferredLanguages {
            if let match = values.first(where: { $0.language == language }) { return match.text }
        }
        return values.first?.text
    }

    /// One label per concept (English where there is one), e.g. each creator's name.
    static func labels(_ value: Any?) -> [String] {
        let concepts = value as? [Any] ?? (value.map { [$0] } ?? [])
        return concepts.compactMap { concept in
            (concept as? [String: Any]).flatMap { text($0[prefLabel]) }
        }
    }

    private static func tagged(_ value: Any?) -> [(language: String?, text: String)] {
        switch value {
        case let string as String:
            return WallpaperJSON.string(string).map { [(nil, $0)] } ?? []
        case let array as [Any]:
            return array.flatMap { tagged($0) }
        case let object as [String: Any]:
            if let text = WallpaperJSON.string(object["@value"]) {
                return [(object["@language"] as? String, text)]
            }
            // A language map: every key is a language.
            return object.sorted { $0.key < $1.key }.flatMap { language, texts in
                tagged(texts).map { (language, $0.text) }
            }
        default:
            return []
        }
    }
}

/// Resolved works by ID, so a refined search doesn't fetch them again. Misses (works
/// that don't qualify) are kept too.
actor ResolvedItemCache {
    private var items: [String: OnlineWallpaper?] = [:]
    private static let limit = 500

    func lookup(_ itemID: String) -> OnlineWallpaper?? {
        items[itemID]
    }

    func store(_ wallpaper: OnlineWallpaper?, for itemID: String) {
        if items.count >= Self.limit { items.removeAll() }
        items[itemID] = .some(wallpaper)
    }
}
