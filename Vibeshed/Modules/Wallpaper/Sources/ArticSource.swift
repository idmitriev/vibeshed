import Foundation

/// The Art Institute of Chicago's API (https://api.artic.edu/docs/): public-domain
/// artworks, no key, 60 requests a minute. Images come from its IIIF server, which
/// documents 843 px wide images, and 1686 px for public-domain works.
///
/// Since June 2026 that server answers apps with a Cloudflare browser check
/// (https://github.com/art-institute-of-chicago/api-data/issues/9), so searches check
/// that an image comes through and report `.blocked` while it doesn't.
struct ArticSource: WallpaperSource {
    let id = WallpaperSourceID.artic
    var imageHost = ImageHostCheck.shared

    private static let apiURL = URL(string: "https://api.artic.edu/api/v1")!
    private static let iiifURL = URL(string: "https://www.artic.edu/iiif/2")!
    private static let fields = [
        "id", "title", "artist_title", "artist_display", "date_display", "medium_display",
        "image_id", "thumbnail", "is_public_domain",
    ].joined(separator: ",")
    /// The Art Institute asks for an `AIC-User-Agent` naming the app and a contact.
    private static let headers = ["AIC-User-Agent": WallpaperHTTP.userAgent]

    func search(_ query: String, options: WallpaperSearchOptions) async throws -> [OnlineWallpaper] {
        let results = try await fetch(query: query, limit: options.limit, page: 1)
        try await checkImageHost(results.first)
        return results.preferring(options.orientation)
    }

    func wallpaper(itemID: String) async throws -> OnlineWallpaper? {
        let url = Self.apiURL.appendingPathComponent("artworks/\(itemID)")
            .appending(queryItems: [URLQueryItem(name: "fields", value: Self.fields)])
        let json = try await WallpaperHTTP.json(url, source: id, headers: Self.headers)
        return (json["data"] as? [String: Any]).flatMap(Self.wallpaper)
    }

    /// One of the museum's highlighted public-domain paintings (about 120).
    func random(options: WallpaperSearchOptions) async throws -> OnlineWallpaper? {
        let results = try await fetch(query: "", limit: 20, page: Int.random(in: 1 ... 6))
        let pick = results.filter { options.orientation.matches($0.aspectRatio) }.randomElement()
            ?? results.randomElement()
        try await checkImageHost(pick)
        return pick
    }

    /// Public-domain works with an image; an empty query gives the museum's highlighted paintings.
    private func fetch(query: String, limit: Int, page: Int) async throws -> [OnlineWallpaper] {
        var filters: [[String: Any]] = [
            ["term": ["is_public_domain": true]],
            ["exists": ["field": "image_id"]],
        ]
        if query.isEmpty {
            filters += [["term": ["is_boosted": true]], ["term": ["artwork_type_id": 1]]]
        }
        let params = try JSONSerialization.data(withJSONObject: ["query": ["bool": ["filter": filters]]])
        var items = [
            URLQueryItem(name: "params", value: String(bytes: params, encoding: .utf8)),
            URLQueryItem(name: "fields", value: Self.fields),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "page", value: String(page)),
        ]
        if !query.isEmpty {
            items.append(URLQueryItem(name: "q", value: query))
        }
        let url = Self.apiURL.appendingPathComponent("artworks/search").appending(queryItems: items)
        return try await Self.parseSearch(WallpaperHTTP.json(url, source: id, headers: Self.headers))
    }

    private func checkImageHost(_ wallpaper: OnlineWallpaper?) async throws {
        guard let wallpaper, await !imageHost.isOpen(wallpaper.thumbnailURL, source: id) else { return }
        throw WallpaperSourceError.blocked(id)
    }

    // MARK: - Parsing

    static func parseSearch(_ json: [String: Any]) -> [OnlineWallpaper] {
        (json["data"] as? [[String: Any]] ?? []).compactMap(wallpaper)
    }

    static func wallpaper(_ json: [String: Any]) -> OnlineWallpaper? {
        guard let itemID = WallpaperJSON.string(json["id"]),
              let imageID = WallpaperJSON.string(json["image_id"]),
              json["is_public_domain"] as? Bool != false
        else { return nil }
        let image = iiifURL.appendingPathComponent(imageID)
        let thumbnail = json["thumbnail"] as? [String: Any] ?? [:]
        let width = WallpaperJSON.int(thumbnail["width"])
        let height = WallpaperJSON.int(thumbnail["height"])
        return OnlineWallpaper(
            source: .artic,
            sourceItemID: itemID,
            title: WallpaperJSON.string(json["title"]) ?? "Untitled",
            credit: WallpaperJSON.string(json["artist_title"])
                ?? WallpaperJSON.string(json["artist_display"])?.components(separatedBy: "\n").first,
            creditURL: nil,
            date: WallpaperJSON.string(json["date_display"]),
            detail: WallpaperJSON.string(json["medium_display"]),
            pageURL: URL(string: "https://www.artic.edu/artworks/\(itemID)"),
            thumbnailURL: image.appendingPathComponent("full/200,/0/default.jpg"),
            previewURL: image.appendingPathComponent("full/843,/0/default.jpg"),
            image: .fixed(image.appendingPathComponent("full/1686,/0/default.jpg")),
            pixelWidth: width,
            pixelHeight: height,
            aspectRatio: WallpaperJSON.aspectRatio(width: width.map(Double.init), height: height.map(Double.init)),
            colors: [],
            license: "Public domain (CC0)",
            downloadTrackingURL: nil
        )
    }
}

/// Whether an image server lets apps through, checked at most every half hour per host.
actor ImageHostCheck {
    static let shared = ImageHostCheck()

    private static let lifetime: Duration = .seconds(30 * 60)
    private var results: [String: (isOpen: Bool, checkedAt: ContinuousClock.Instant)] = [:]

    /// False only when fetching `sample` gets a browser check; other failures don't count.
    func isOpen(_ sample: URL, source: WallpaperSourceID) async -> Bool {
        let host = sample.host() ?? sample.absoluteString
        if let result = results[host], result.checkedAt.duration(to: .now) < Self.lifetime {
            return result.isOpen
        }
        var request = URLRequest(url: sample)
        request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
        let isOpen: Bool
        do {
            let (_, response) = try await WallpaperHTTP.session.data(for: request)
            try WallpaperHTTP.check(response, source: source)
            isOpen = true
        } catch WallpaperSourceError.blocked {
            isOpen = false
        } catch {
            // A network hiccup isn't a verdict; look again next time.
            return true
        }
        results[host] = (isOpen, .now)
        return isOpen
    }
}
