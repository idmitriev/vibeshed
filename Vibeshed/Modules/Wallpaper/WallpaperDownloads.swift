import AppKit
import Foundation
import UniformTypeIdentifiers

/// Downloaded wallpapers on disk. Each image keeps its own file (`met-436524.jpg`) —
/// macOS won't redraw a wallpaper whose URL didn't change — and records its image and
/// web page as "Where from" (`kMDItemWhereFroms`, like a browser download), which
/// "Open Wallpaper Source Page" reads back.
enum WallpaperDownloads {
    /// Unset `downloadDirectory`: a folder of its own, beside the theme's generated ones
    /// (whose pruning would delete a subfolder).
    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Vibeshed/Online Wallpapers", isDirectory: true)
    }

    /// Downloads kept in the default directory; older ones go (never one on screen).
    static let keptDownloads = 40

    static func directory(for config: WallpaperConfig) -> URL {
        guard let path = config.downloadDirectory else { return defaultDirectory }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// The image file for `wallpaper`, downloading it unless an earlier download is there.
    static func file(
        for wallpaper: OnlineWallpaper,
        longestSide: Int,
        in directory: URL
    ) async throws -> URL {
        let fileManager = FileManager.default
        let stem = fileStem(for: wallpaper)
        let existing = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .first { $0.deletingPathExtension().lastPathComponent == stem }
        if let existing {
            // Touched so pruning counts it as recent.
            try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: existing.path)
            return existing
        }

        let url = wallpaper.downloadURL(longestSide: longestSide)
        let (temporary, response) = try await WallpaperHTTP.session.download(from: url)
        defer { try? fileManager.removeItem(at: temporary) }
        try WallpaperHTTP.check(response, source: wallpaper.source)
        guard let type = response.mimeType.flatMap({ UTType(mimeType: $0) }), type.conforms(to: .image) else {
            throw WallpaperSourceError.notAnImage(wallpaper.source)
        }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(stem)
            .appendingPathExtension(type.preferredFilenameExtension ?? "jpg")
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: temporary, to: destination)
        setWhereFroms([url, wallpaper.pageURL].compactMap(\.self), of: destination)
        return destination
    }

    /// `<source>-<id>`, with anything unsafe in a file name replaced.
    static func fileStem(for wallpaper: OnlineWallpaper) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let itemID = String(wallpaper.sourceItemID.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        return "\(wallpaper.source.rawValue)-\(itemID)"
    }

    /// Deletes all but the most recent downloads in the default directory, sparing any on screen.
    @MainActor
    static func prune() {
        let inUse = Set(NSScreen.screens.compactMap {
            NSWorkspace.shared.desktopImageURL(for: $0)?.standardizedFileURL
        })
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: defaultDirectory, includingPropertiesForKeys: Array(keys)
        ) else { return }
        let byAge = files
            .filter { (try? $0.resourceValues(forKeys: keys).isRegularFile) == true }
            .sorted {
                let lhs = (try? $0.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
                return lhs > rhs
            }
        for file in byAge.dropFirst(keptDownloads) where !inUse.contains(file.standardizedFileURL) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: - Where from

    private static let whereFromsAttribute = "com.apple.metadata:kMDItemWhereFroms"

    static func setWhereFroms(_ urls: [URL], of file: URL) {
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: urls.map(\.absoluteString), format: .binary, options: 0
        ) else { return }
        _ = data.withUnsafeBytes { bytes in
            setxattr(file.path, whereFromsAttribute, bytes.baseAddress, bytes.count, 0, 0)
        }
    }

    /// The "Where from" URLs of `file`: the image first, then the page it came from.
    static func whereFroms(of file: URL) -> [URL] {
        let size = getxattr(file.path, whereFromsAttribute, nil, 0, 0, 0)
        guard size > 0 else { return [] }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { bytes in
            getxattr(file.path, whereFromsAttribute, bytes.baseAddress, size, 0, 0)
        }
        guard read == size,
              let strings = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String]
        else { return [] }
        return strings.compactMap(URL.init(string:))
    }

    /// The web page a file came from: the second "Where from" (browsers put the page
    /// after the file), else the only one.
    static func sourcePage(of file: URL) -> URL? {
        let urls = whereFroms(of: file).filter { $0.scheme == "https" || $0.scheme == "http" }
        return urls.count > 1 ? urls[1] : urls.first
    }
}

/// Puts an image on the desktop of every screen, as System Settings does for the
/// current Space. Uses `NSWorkspace`, so it needs no permission.
@MainActor
enum DesktopPicture {
    /// The main screen's wallpaper file.
    static var current: URL? {
        (NSScreen.main ?? NSScreen.screens.first).flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
    }

    /// Sets `file` on every screen, placed as `placement` decides for the screen's
    /// width / height. Returns the placements, main screen first.
    @discardableResult
    static func set(_ file: URL, placement: (Double) -> WallpaperPlacement) throws -> [WallpaperPlacement] {
        try NSScreen.screens.map { screen in
            let frame = screen.frame
            let chosen = placement(frame.height > 0 ? frame.width / frame.height : 16 / 10)
            var options: [NSWorkspace.DesktopImageOptionKey: Any] = [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
            ]
            switch chosen {
            case .fill:
                options[.allowClipping] = true
            case let .fit(matte):
                options[.allowClipping] = false
                options[.fillColor] = matte.nsColor
            }
            try NSWorkspace.shared.setDesktopImageURL(file, for: screen, options: options)
            return chosen
        }
    }

    /// The longer side of the largest screen in pixels, capped at 6K: the size to download.
    static func longestScreenSide() -> Int {
        let sides = NSScreen.screens.map { max($0.frame.width, $0.frame.height) * $0.backingScaleFactor }
        return Int(min(sides.max() ?? 3840, 6144))
    }
}
