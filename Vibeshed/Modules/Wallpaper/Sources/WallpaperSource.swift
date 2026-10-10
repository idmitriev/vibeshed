import Foundation

/// A website or museum collection that `WallpaperModule` searches.
protocol WallpaperSource: Sendable {
    var id: WallpaperSourceID { get }

    /// Images matching `query`, best first. An empty query asks for a featured selection.
    func search(_ query: String, options: WallpaperSearchOptions) async throws -> [OnlineWallpaper]

    /// One image by the source's own ID: for IDs that come from a URI or alias rather
    /// than a search the module still remembers.
    func wallpaper(itemID: String) async throws -> OnlineWallpaper?

    /// A random pick from the source's featured images.
    func random(options: WallpaperSearchOptions) async throws -> OnlineWallpaper?
}

struct WallpaperSearchOptions: Sendable, Equatable {
    var limit: Int
    var orientation: WallpaperOrientation
}

enum WallpaperSourceError: Error, LocalizedError, Equatable {
    case missingKey(WallpaperSourceID)
    case unauthorized(WallpaperSourceID)
    case rateLimited(WallpaperSourceID)
    /// The server answered with a bot check (a Cloudflare challenge) that only a browser can pass.
    case blocked(WallpaperSourceID)
    case http(WallpaperSourceID, status: Int)
    case badResponse(WallpaperSourceID)
    case notAnImage(WallpaperSourceID)

    var source: WallpaperSourceID {
        switch self {
        case let .missingKey(source), let .unauthorized(source), let .rateLimited(source),
             let .blocked(source), let .http(source, _), let .badResponse(source), let .notAnImage(source):
            source
        }
    }

    var errorDescription: String? {
        let name = source.displayName
        switch self {
        case .missingKey:
            return "\(name) needs an access key in config.yaml"
        case .unauthorized:
            return "\(name) turned down the access key in config.yaml"
        case .rateLimited:
            return "\(name)'s rate limit is used up — try again later"
        case .blocked:
            return "\(name) is turning away apps with a browser check"
        case let .http(_, status):
            return "\(name) answered with HTTP \(status)"
        case .badResponse:
            return "\(name) sent a response Vibeshed doesn't understand"
        case .notAnImage:
            return "\(name) didn't send an image"
        }
    }
}

/// GET requests shared by the sources.
enum WallpaperHTTP {
    /// Identifies Vibeshed to the APIs (the Art Institute asks for a contact in `AIC-User-Agent`).
    static let userAgent = "Vibeshed (https://github.com/idmitriev/vibeshed)"

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: configuration)
    }()

    /// The JSON object at `url`.
    static func json(
        _ url: URL,
        source: WallpaperSourceID,
        headers: [String: String] = [:]
    ) async throws -> [String: Any] {
        var headers = headers
        headers["Accept"] = headers["Accept"] ?? "application/json"
        let data = try await data(url, source: source, headers: headers)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WallpaperSourceError.badResponse(source)
        }
        return object
    }

    static func data(_ url: URL, source: WallpaperSourceID, headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url)
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let (data, response) = try await session.data(for: request)
        do {
            try check(response, source: source)
            return data
        } catch let WallpaperSourceError.http(_, status) where status == 403 || status >= 500 {
            // The Met's CDN turns away the odd request with a bare 403; moments later it goes through.
            try await Task.sleep(for: .milliseconds(500))
            let (data, response) = try await session.data(for: request)
            try check(response, source: source)
            return data
        }
    }

    /// Throws for anything but a 2xx answer.
    static func check(_ response: URLResponse, source: WallpaperSourceID) throws {
        guard let http = response as? HTTPURLResponse else { throw WallpaperSourceError.badResponse(source) }
        switch http.statusCode {
        case 200 ..< 300:
            return
        case 401:
            throw WallpaperSourceError.unauthorized(source)
        case 429:
            throw WallpaperSourceError.rateLimited(source)
        case 403 where http.value(forHTTPHeaderField: "cf-mitigated") == "challenge":
            throw WallpaperSourceError.blocked(source)
        case 403 where http.value(forHTTPHeaderField: "X-Ratelimit-Remaining") == "0":
            // Unsplash reports a spent hourly limit as 403.
            throw WallpaperSourceError.rateLimited(source)
        default:
            throw WallpaperSourceError.http(source, status: http.statusCode)
        }
    }
}

/// Reading loosely typed JSON.
enum WallpaperJSON {
    /// A trimmed, non-empty string.
    static func string(_ value: Any?) -> String? {
        if let number = value as? NSNumber {
            // JSON true/false parse to NSNumber too.
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? nil : number.stringValue
        }
        guard let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty
        else { return nil }
        return string
    }

    static func url(_ value: Any?) -> URL? {
        string(value).flatMap(URL.init(string:))
    }

    static func int(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        return string(value).flatMap { Int($0) }
    }

    static func double(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        return string(value).flatMap { Double($0) }
    }

    /// `width / height`, when both are positive.
    static func aspectRatio(width: Double?, height: Double?) -> Double? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return width / height
    }
}

enum WallpaperLookup {
    /// Looks `identifiers` up concurrently and returns the wallpapers in their order,
    /// dropping nil answers. A failed lookup drops only its item; when every lookup
    /// fails, the first error is thrown.
    static func all(
        _ identifiers: [String],
        lookup: @escaping @Sendable (String) async throws -> OnlineWallpaper?
    ) async throws -> [OnlineWallpaper] {
        let outcomes = await withTaskGroup(of: (Int, Result<OnlineWallpaper?, Error>).self) { group in
            for (index, itemID) in identifiers.enumerated() {
                group.addTask {
                    // Await first, then pair: release builds miscompile `try await (index, .success(…))`
                    // in `WallpaperModule.search(_:in:)`; this copy hasn't gone wrong, but could.
                    do {
                        let wallpaper = try await lookup(itemID)
                        return (index, .success(wallpaper))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            var outcomes: [(Int, Result<OnlineWallpaper?, Error>)] = []
            for await outcome in group {
                outcomes.append(outcome)
            }
            return outcomes.sorted { $0.0 < $1.0 }.map(\.1)
        }
        let failures = outcomes.compactMap { outcome -> Error? in
            if case let .failure(error) = outcome { return error }
            return nil
        }
        if !outcomes.isEmpty, failures.count == outcomes.count, let first = failures.first {
            throw first
        }
        return outcomes.compactMap { try? $0.get() }.compactMap(\.self)
    }
}

extension [OnlineWallpaper] {
    /// Results whose shape fits `orientation` first, keeping the order within each group.
    /// For sources that can't filter by shape themselves.
    func preferring(_ orientation: WallpaperOrientation) -> [OnlineWallpaper] {
        let matching = filter { orientation.matches($0.aspectRatio) }
        return matching + filter { !orientation.matches($0.aspectRatio) }
    }
}

extension String {
    /// nil for an empty string.
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
