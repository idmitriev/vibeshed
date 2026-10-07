import Foundation

/// Unsplash's API (https://unsplash.com/documentation). Needs an access key from an app
/// registered at https://unsplash.com/oauth/applications: 50 requests an hour until
/// Unsplash approves the app for production.
///
/// The guidelines ask apps to show images from the URLs the API returns (thumbnails and
/// previews do), credit the photographer with links carrying `utm_source`, and call a
/// photo's `download_location` when it's used (setting it as the wallpaper does).
struct UnsplashSource: WallpaperSource {
    let id = WallpaperSourceID.unsplash
    var accessKey: String?

    private static let baseURL = URL(string: "https://api.unsplash.com")!
    /// The topic shown for an empty query and picked from at random.
    private static let featuredTopic = "wallpapers"
    private static let referral = [
        URLQueryItem(name: "utm_source", value: "vibeshed"),
        URLQueryItem(name: "utm_medium", value: "referral"),
    ]

    func search(_ query: String, options: WallpaperSearchOptions) async throws -> [OnlineWallpaper] {
        let limit = URLQueryItem(name: "per_page", value: String(min(options.limit, 30)))
        if query.isEmpty {
            let json = try await array("topics/\(Self.featuredTopic)/photos", [limit] + orientation(options))
            return json.compactMap(Self.wallpaper)
        }
        let url = Self.baseURL.appendingPathComponent("search/photos").appending(queryItems: [
            URLQueryItem(name: "query", value: query), limit,
            URLQueryItem(name: "content_filter", value: "high"),
        ] + orientation(options))
        let json = try await WallpaperHTTP.json(url, source: id, headers: headers())
        return (json["results"] as? [[String: Any]] ?? []).compactMap(Self.wallpaper)
    }

    func wallpaper(itemID: String) async throws -> OnlineWallpaper? {
        let url = Self.baseURL.appendingPathComponent("photos/\(itemID)")
        return try await Self.wallpaper(WallpaperHTTP.json(url, source: id, headers: headers()))
    }

    func random(options: WallpaperSearchOptions) async throws -> OnlineWallpaper? {
        let page = URLQueryItem(name: "page", value: String(Int.random(in: 1 ... 10)))
        let perPage = URLQueryItem(name: "per_page", value: "30")
        let json = try await array("topics/\(Self.featuredTopic)/photos", [page, perPage] + orientation(options))
        return json.compactMap(Self.wallpaper).randomElement()
    }

    /// Tells Unsplash the photo was used, as its guidelines ask.
    func trackDownload(_ wallpaper: OnlineWallpaper) async throws {
        guard let url = wallpaper.downloadTrackingURL else { return }
        _ = try await WallpaperHTTP.data(url, source: id, headers: headers())
    }

    private func headers() throws -> [String: String] {
        guard let accessKey, !accessKey.isEmpty else { throw WallpaperSourceError.missingKey(id) }
        return ["Authorization": "Client-ID \(accessKey)", "Accept-Version": "v1"]
    }

    private func orientation(_ options: WallpaperSearchOptions) -> [URLQueryItem] {
        options.orientation == .any ? [] : [URLQueryItem(name: "orientation", value: options.orientation.rawValue)]
    }

    private func array(_ path: String, _ query: [URLQueryItem]) async throws -> [[String: Any]] {
        let url = Self.baseURL.appendingPathComponent(path).appending(queryItems: query)
        let data = try await WallpaperHTTP.data(url, source: id, headers: headers())
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw WallpaperSourceError.badResponse(id)
        }
        return array
    }

    // MARK: - Parsing

    static func wallpaper(_ json: [String: Any]) -> OnlineWallpaper? {
        guard let itemID = WallpaperJSON.string(json["id"]),
              let urls = json["urls"] as? [String: Any],
              let raw = WallpaperJSON.url(urls["raw"]),
              let thumbnail = WallpaperJSON.url(urls["thumb"]) ?? WallpaperJSON.url(urls["small"])
        else { return nil }
        let links = json["links"] as? [String: Any] ?? [:]
        let user = json["user"] as? [String: Any] ?? [:]
        let photographer = WallpaperJSON.string(user["name"]) ?? WallpaperJSON.string(user["username"])
        let description = WallpaperJSON.string(json["description"])
        let altText = WallpaperJSON.string(json["alt_description"])
        let width = WallpaperJSON.int(json["width"])
        let height = WallpaperJSON.int(json["height"])
        return OnlineWallpaper(
            source: .unsplash,
            sourceItemID: itemID,
            title: (description ?? altText).map(sentenceCased)
                ?? "Photo by \(photographer ?? "an Unsplash photographer")",
            credit: photographer,
            creditURL: WallpaperJSON.url((user["links"] as? [String: Any])?["html"])?.appending(queryItems: referral),
            date: nil,
            detail: description != nil ? altText.map(sentenceCased) : nil,
            pageURL: WallpaperJSON.url(links["html"])?.appending(queryItems: referral),
            thumbnailURL: thumbnail,
            previewURL: WallpaperJSON.url(urls["regular"]) ?? thumbnail,
            image: .imgix(raw),
            pixelWidth: width,
            pixelHeight: height,
            aspectRatio: WallpaperJSON.aspectRatio(width: width.map(Double.init), height: height.map(Double.init)),
            colors: WallpaperJSON.string(json["color"]).map { [$0] } ?? [],
            license: "Unsplash License",
            downloadTrackingURL: WallpaperJSON.url(links["download_location"])
        )
    }

    /// Alt texts come lowercased ("a mountain range at dusk").
    private static func sentenceCased(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
