import Foundation

/// The Metropolitan Museum of Art's collection API (https://metmuseum.github.io/): no
/// key, up to 80 requests a second. Search (v1.1; v1 was retired on 2026-10-01) returns
/// object IDs only, and each object is fetched for its details. It can't filter by
/// rights, and only open-access objects come with images, so a few extra are fetched.
/// Searches are limited to paintings: without that, a query matches mostly ceramics,
/// textiles and in-copyright prints.
struct MetSource: WallpaperSource {
    let id = WallpaperSourceID.met
    var cache = ResolvedItemCache()

    private static let apiURL = URL(string: "https://collectionapi.metmuseum.org/public/collection")!
    private static let paintings = [
        URLQueryItem(name: "hasImages", value: "true"),
        URLQueryItem(name: "medium", value: "Paintings"),
    ]
    /// The museum's highlighted paintings (about 420): the featured selection.
    private static let highlights = [
        URLQueryItem(name: "q", value: "*"),
        URLQueryItem(name: "isHighlight", value: "true"),
    ]

    func search(_ query: String, options: WallpaperSearchOptions) async throws -> [OnlineWallpaper] {
        let terms = query.isEmpty ? Self.highlights : [URLQueryItem(name: "q", value: query)]
        // About half the hits are in copyright, without an image. The API answers about
        // ten objects a second, so asking for more only waits longer.
        let identifiers = try await search(terms, limit: options.limit * 2, offset: 0)
        let found = try await WallpaperLookup.all(identifiers) { try await object($0) }
        return Array(found.prefix(options.limit)).preferring(options.orientation)
    }

    func wallpaper(itemID: String) async throws -> OnlineWallpaper? {
        try await object(itemID)
    }

    /// From a random page of the highlights, preferring the configured orientation.
    func random(options: WallpaperSearchOptions) async throws -> OnlineWallpaper? {
        for _ in 0 ..< 2 {
            let identifiers = try await search(Self.highlights, limit: 20, offset: Int.random(in: 0 ... 20) * 20)
            let found = try await WallpaperLookup.all(identifiers) { try await object($0) }
            if let pick = found.filter({ options.orientation.matches($0.aspectRatio) }).randomElement()
                ?? found.randomElement()
            {
                return pick
            }
        }
        return nil
    }

    private func search(_ terms: [URLQueryItem], limit: Int, offset: Int) async throws -> [String] {
        let url = Self.apiURL.appendingPathComponent("v1.1/search").appending(queryItems: terms + Self.paintings + [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ])
        return try await Self.parseSearch(WallpaperHTTP.json(url, source: id))
    }

    private func object(_ itemID: String) async throws -> OnlineWallpaper? {
        if let cached = await cache.lookup(itemID) { return cached }
        let url = Self.apiURL.appendingPathComponent("v1/objects/\(itemID)")
        let wallpaper = try await Self.wallpaper(WallpaperHTTP.json(url, source: id))
        await cache.store(wallpaper, for: itemID)
        return wallpaper
    }

    // MARK: - Parsing

    static func parseSearch(_ json: [String: Any]) -> [String] {
        (json["objectIDs"] as? [Any] ?? []).compactMap(WallpaperJSON.string)
    }

    /// An object from `objects/<id>`; nil unless it's public domain with an image.
    static func wallpaper(_ json: [String: Any]) -> OnlineWallpaper? {
        guard let itemID = WallpaperJSON.string(json["objectID"]),
              json["isPublicDomain"] as? Bool == true,
              let image = WallpaperJSON.url(json["primaryImage"])
        else { return nil }
        let small = WallpaperJSON.url(json["primaryImageSmall"]) ?? image
        return OnlineWallpaper(
            source: .met,
            sourceItemID: itemID,
            title: WallpaperJSON.string(json["title"]) ?? "Untitled",
            credit: WallpaperJSON.string(json["artistDisplayName"]) ?? WallpaperJSON.string(json["culture"]),
            creditURL: nil,
            date: WallpaperJSON.string(json["objectDate"]),
            detail: WallpaperJSON.string(json["medium"]),
            pageURL: WallpaperJSON.url(json["objectURL"]),
            thumbnailURL: small,
            previewURL: small,
            image: .fixed(image),
            pixelWidth: nil,
            pixelHeight: nil,
            aspectRatio: aspectRatio(json["measurements"]),
            colors: [],
            license: "Public domain (CC0)",
            downloadTrackingURL: nil
        )
    }

    /// Width / height of the "Overall" (else the first) measured element.
    private static func aspectRatio(_ value: Any?) -> Double? {
        let elements = value as? [[String: Any]] ?? []
        let element = elements.first { $0["elementName"] as? String == "Overall" } ?? elements.first
        let measurements = element?["elementMeasurements"] as? [String: Any]
        return WallpaperJSON.aspectRatio(
            width: WallpaperJSON.double(measurements?["Width"]),
            height: WallpaperJSON.double(measurements?["Height"])
        )
    }
}
