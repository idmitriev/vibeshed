import Foundation

/// Where online wallpapers come from. The raw value is the name config uses and the
/// prefix of result IDs (`met:436524`).
enum WallpaperSourceID: String, CaseIterable, Codable, Sendable {
    case wallhaven
    case unsplash
    case artic
    case rijksmuseum
    case met

    var displayName: String {
        switch self {
        case .wallhaven: "Wallhaven"
        case .unsplash: "Unsplash"
        case .artic: "Art Institute of Chicago"
        case .rijksmuseum: "Rijksmuseum"
        case .met: "The Met"
        }
    }

    /// Short name for list rows.
    var shortName: String {
        switch self {
        case .artic: "Art Institute"
        default: displayName
        }
    }

    var iconName: String {
        switch self {
        case .wallhaven: "photo.on.rectangle"
        case .unsplash: "camera"
        case .artic, .rijksmuseum, .met: "building.columns"
        }
    }

    /// Artwork keeps its whole composition: it's fitted on a matte unless its shape is
    /// close to the screen's. Photos and wallpapers fill the screen.
    var isArtwork: Bool {
        switch self {
        case .wallhaven, .unsplash: false
        case .artic, .rijksmuseum, .met: true
        }
    }
}

/// Which way up results should be, where a source can filter or rank by it.
enum WallpaperOrientation: String, Codable, Sendable, CaseIterable {
    case landscape
    case portrait
    case any

    /// Whether an image `aspectRatio` (width / height) fits. Unknown shapes pass.
    func matches(_ aspectRatio: Double?) -> Bool {
        guard let aspectRatio else { return true }
        switch self {
        case .landscape: return aspectRatio > 1
        case .portrait: return aspectRatio < 1
        case .any: return true
        }
    }
}

/// One image a source offers: what the picker shows and where to download it from.
struct OnlineWallpaper: Sendable, Equatable, Identifiable {
    /// How to fetch the image at a size for the screen.
    enum ImageLocation: Sendable, Equatable {
        /// A file of fixed size (Wallhaven and Met originals).
        case fixed(URL)
        /// A IIIF Image API service (`…/iiif/2/<id>`): asks for the screen's size.
        case iiif(URL)
        /// An imgix URL (Unsplash's `raw`), sized with `w`.
        case imgix(URL)
    }

    let source: WallpaperSourceID
    /// The source's own ID for the image or artwork.
    let sourceItemID: String
    let title: String
    /// The artist or photographer.
    let credit: String?
    /// A link to the artist or photographer, when the source has one.
    let creditURL: URL?
    /// When the artwork was made, as the museum writes it ("c. 1680").
    let date: String?
    /// One more line about the image: a photo's description, an artwork's medium.
    let detail: String?
    /// The image's page on the source's website.
    let pageURL: URL?
    let thumbnailURL: URL
    /// A medium-size image for the preview panel.
    let previewURL: URL
    let image: ImageLocation
    /// Pixel size, when the source reports it.
    let pixelWidth: Int?
    let pixelHeight: Int?
    /// Width / height, from pixels or the artwork's physical size.
    let aspectRatio: Double?
    /// Dominant colors as `#rrggbb` (Wallhaven).
    let colors: [String]
    /// Usage terms, e.g. "Public domain". Wallhaven uploads have none to report.
    let license: String?
    /// Unsplash asks apps to call this when a photo is used.
    let downloadTrackingURL: URL?

    var id: String {
        Self.optionID(source: source, itemID: sourceItemID)
    }

    static func optionID(source: WallpaperSourceID, itemID: String) -> String {
        "\(source.rawValue):\(itemID)"
    }

    /// Splits an option ID into its source and the source's own ID.
    static func parseOptionID(_ optionID: String) -> (source: WallpaperSourceID, itemID: String)? {
        guard let separator = optionID.firstIndex(of: ":"),
              let source = WallpaperSourceID(rawValue: String(optionID[..<separator]))
        else { return nil }
        let itemID = String(optionID[optionID.index(after: separator)...])
        return itemID.isEmpty ? nil : (source, itemID)
    }

    /// "3840 × 2160", when the pixel size is known.
    var resolution: String? {
        guard let pixelWidth, let pixelHeight else { return nil }
        return "\(pixelWidth) × \(pixelHeight)"
    }

    /// The URL to download for a screen whose longer side is `longestSide` pixels.
    func downloadURL(longestSide: Int) -> URL {
        switch image {
        case let .fixed(url):
            return url
        case let .iiif(service):
            // Fits within a square of the screen's longer side; never upscaled (no `^`).
            return service.appendingPathComponent("full/!\(longestSide),\(longestSide)/0/default.jpg")
        case let .imgix(raw):
            return raw.appending(queryItems: [
                URLQueryItem(name: "w", value: String(longestSide)),
                URLQueryItem(name: "fit", value: "max"),
                URLQueryItem(name: "fm", value: "jpg"),
                URLQueryItem(name: "q", value: "90"),
            ])
        }
    }
}
