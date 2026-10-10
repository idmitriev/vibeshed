import Foundation

/// wallhaven.cc's API (https://wallhaven.cc/help/api). Works without a key for SFW
/// images; a key from the account settings lifts nothing else Vibeshed uses, but is sent
/// when set. 45 requests a minute.
struct WallhavenSource: WallpaperSource {
    let id = WallpaperSourceID.wallhaven
    var apiKey: String?
    /// Category names: general, anime, people.
    var categories: [String]

    private static let baseURL = URL(string: "https://wallhaven.cc/api/v1")!
    /// Smallest image size offered.
    private static let minimumResolution = "1920x1080"

    func search(_ query: String, options: WallpaperSearchOptions) async throws -> [OnlineWallpaper] {
        let sorting: [URLQueryItem] = query.isEmpty
            ? [.init(name: "sorting", value: "toplist"), .init(name: "topRange", value: "1M")]
            : [.init(name: "q", value: query), .init(name: "sorting", value: "relevance")]
        return try await Array(fetch(sorting, options: options).prefix(options.limit))
    }

    func wallpaper(itemID: String) async throws -> OnlineWallpaper? {
        let json = try await WallpaperHTTP.json(
            Self.baseURL.appendingPathComponent("w/\(itemID)"), source: id, headers: headers
        )
        return (json["data"] as? [String: Any]).flatMap(Self.wallpaper)
    }

    /// From the past year's top list, which beats `sorting=random` on quality.
    func random(options: WallpaperSearchOptions) async throws -> OnlineWallpaper? {
        let page = Int.random(in: 1 ... 5)
        return try await fetch(
            [.init(name: "sorting", value: "toplist"), .init(name: "topRange", value: "1y"),
             .init(name: "page", value: String(page))],
            options: options
        ).randomElement()
    }

    private var headers: [String: String] {
        apiKey.map { ["X-API-Key": $0] } ?? [:]
    }

    private func fetch(_ items: [URLQueryItem], options: WallpaperSearchOptions) async throws -> [OnlineWallpaper] {
        var query = items + [
            .init(name: "categories", value: Self.categoryBits(categories)),
            .init(name: "purity", value: "100"),
            .init(name: "atleast", value: Self.minimumResolution),
        ]
        if options.orientation != .any {
            query.append(.init(name: "ratios", value: options.orientation.rawValue))
        }
        let url = Self.baseURL.appendingPathComponent("search").appending(queryItems: query)
        return try await Self.parseSearch(WallpaperHTTP.json(url, source: id, headers: headers))
    }

    /// "110" for general + anime: the API's on/off string in general, anime, people order.
    static func categoryBits(_ categories: [String]) -> String {
        let names = Set(categories.map { $0.lowercased() })
        let bits = ["general", "anime", "people"].map { names.contains($0) ? "1" : "0" }.joined()
        return bits == "000" ? "111" : bits
    }

    // MARK: - Parsing

    static func parseSearch(_ json: [String: Any]) -> [OnlineWallpaper] {
        (json["data"] as? [[String: Any]] ?? []).compactMap(wallpaper)
    }

    static func wallpaper(_ json: [String: Any]) -> OnlineWallpaper? {
        guard let itemID = WallpaperJSON.string(json["id"]),
              let image = WallpaperJSON.url(json["path"]),
              let thumbs = json["thumbs"] as? [String: Any],
              let thumbnail = WallpaperJSON.url(thumbs["small"])
        else { return nil }
        let width = WallpaperJSON.int(json["dimension_x"])
        let height = WallpaperJSON.int(json["dimension_y"])
        let favorites = WallpaperJSON.int(json["favorites"]) ?? 0
        let category = WallpaperJSON.string(json["category"])?.capitalized
        let tags = (json["tags"] as? [[String: Any]] ?? []).compactMap { WallpaperJSON.string($0["name"]) }
        let resolution = width.flatMap { width in height.map { "\(width) × \($0)" } }
        return OnlineWallpaper(
            source: .wallhaven,
            sourceItemID: itemID,
            title: tags.prefix(3).joined(separator: ", ").nonEmpty ?? resolution ?? "Wallpaper \(itemID)",
            credit: ((json["uploader"] as? [String: Any])?["username"]).flatMap(WallpaperJSON.string),
            creditURL: nil,
            date: nil,
            detail: [category, favorites > 0 ? "\(favorites) favorites" : nil].compactMap(\.self)
                .joined(separator: " · ").nonEmpty,
            pageURL: WallpaperJSON.url(json["url"]),
            thumbnailURL: thumbnail,
            previewURL: WallpaperJSON.url(thumbs["large"]) ?? thumbnail,
            image: .fixed(image),
            pixelWidth: width,
            pixelHeight: height,
            aspectRatio: WallpaperJSON.aspectRatio(width: width.map(Double.init), height: height.map(Double.init)),
            colors: json["colors"] as? [String] ?? [],
            license: nil,
            downloadTrackingURL: nil
        )
    }
}
