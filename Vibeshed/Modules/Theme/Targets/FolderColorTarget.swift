import AppKit
import Foundation
import OSLog

private let log = Log.module("theme")

/// Folder color, two ways:
/// - the system-wide "Icon, widget & folder color" (macOS 26+), set to the palette's
///   `folder` color (default: accent) through SkyLight's `SLSIconAppearanceConfiguration`
///   — the same object System Settings › Appearance saves, so the change is live;
/// - a palette-tinted custom icon on each folder listed under `folders:` in config.
struct FolderColorTarget: ThemeTarget {
    let id = ThemeTargetID.folders
    let displayName = "Folder color"
    var supportsPreview: Bool { true }

    func apply(_ request: ThemeApplyRequest) async -> ThemeTargetOutcome {
        let color = request.palette["folder"] ?? request.palette.accent
        let systemApplied = await IconTintConfiguration.apply(color)

        var customized = 0
        if !request.isPreview {
            customized = await Self.tintFolders(request.config.folders, color: color)
        }
        if !systemApplied, customized == 0 {
            return request.config.folders.isEmpty
                ? .skipped("needs macOS 26 or folders listed under theme.folders")
                : .failed("couldn't set folder icons")
        }
        return .applied()
    }

    func snapshot(config _: ThemeConfig) async -> ThemeRestore? {
        guard let saved = await IconTintConfiguration.current() else { return nil }
        return { await IconTintConfiguration.restore(saved) }
    }

    @MainActor
    private static func tintFolders(_ folders: [String], color: ThemeColor) -> Int {
        guard !folders.isEmpty, let icon = tintedFolderIcon(color) else { return 0 }
        var count = 0
        for folder in folders {
            let path = ThemeFiles.expand(folder)
            if NSWorkspace.shared.setIcon(icon, forFile: path, options: []) {
                count += 1
            } else {
                log.warning("Couldn't set folder icon on \(path, privacy: .public)")
            }
        }
        return count
    }

    /// The system folder icon recolored: `.color` blending keeps the icon's shading
    /// (luminance) and takes hue/saturation from the palette; `.destinationIn` then
    /// restores the icon's transparent surroundings.
    @MainActor
    private static func tintedFolderIcon(_ color: ThemeColor) -> NSImage? {
        let size = 512
        let base = NSWorkspace.shared.icon(for: .folder)
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        guard let baseImage = base.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(
                  data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.draw(baseImage, in: rect)
        context.setBlendMode(.color)
        context.setFillColor(color.cgColor)
        context.fill(rect)
        context.setBlendMode(.destinationIn)
        context.draw(baseImage, in: rect)
        guard let tinted = context.makeImage() else { return nil }
        return NSImage(cgImage: tinted, size: NSSize(width: size, height: size))
    }
}

/// Private SkyLight API behind System Settings › Appearance › "Icon, widget & folder
/// color" (macOS 26+). Resolved dynamically; every entry point degrades to a no-op when
/// the class or a selector is missing.
@MainActor
enum IconTintConfiguration {
    struct Saved: Sendable {
        let tintName: UInt32
        let custom: ThemeColor?
        let namePreference: String?
        let colorPreference: String?
    }

    private static let nameKey = "AppleIconAppearanceTintColor"
    private static let colorKey = "AppleIconAppearanceCustomTintColor"

    /// Order of SkyLight's tint-name table; the enum value is the index + 1 (0 = none).
    private static let tintNames = ["Hardware", "Red", "Orange", "Yellow", "Green", "Blue",
                                    "Purple", "Pink", "Graphite", "Other"]

    private typealias GetU32 = @convention(c) (AnyObject, Selector) -> UInt32
    private typealias SetU32 = @convention(c) (AnyObject, Selector, UInt32) -> Void
    private typealias GetColor = @convention(c) (AnyObject, Selector) -> Unmanaged<CGColor>?
    private typealias SetColor = @convention(c) (AnyObject, Selector, CGColor?) -> Void
    private typealias Save = @convention(c) (AnyObject, Selector) -> Void

    static func apply(_ color: ThemeColor) -> Bool {
        guard let config = fetch(), mappingIsVerified(config),
              let other = tintNames.firstIndex(of: "Other")
        else { return false }
        // The preferences behind the setting (format from SkyLight's own string table),
        // so the color also holds across logins if the live update doesn't take.
        SystemPreferences.set("Other", forKey: nameKey)
        SystemPreferences.set(
            String(format: "%f %f %f %f", color.red, color.green, color.blue, 1.0), forKey: colorKey
        )
        return write(config, tintName: UInt32(other + 1), custom: color)
    }

    static func current() -> Saved? {
        guard let config = fetch(),
              let tintName = call(config, "iconTintColorName", as: GetU32.self)
        else { return nil }
        let customColor = call(config, "otherIconTintColor", as: GetColor.self)?.takeUnretainedValue()
        let custom = customColor
            .flatMap { NSColor(cgColor: $0) }
            .flatMap(ThemeColor.init(nsColor:))
        return Saved(
            tintName: tintName,
            custom: custom,
            namePreference: SystemPreferences.value(nameKey) as? String,
            colorPreference: SystemPreferences.value(colorKey) as? String
        )
    }

    static func restore(_ saved: Saved) {
        SystemPreferences.set(saved.namePreference, forKey: nameKey)
        SystemPreferences.set(saved.colorPreference, forKey: colorKey)
        guard let config = fetch() else { return }
        _ = write(config, tintName: saved.tintName, custom: saved.custom)
    }

    private static func write(_ config: NSObject, tintName: UInt32, custom: ThemeColor?) -> Bool {
        guard let setName = function(config, "setIconTintColorName:", as: SetU32.self),
              let setColor = function(config, "setOtherIconTintColor:", as: SetColor.self),
              let save = function(config, "save", as: Save.self)
        else { return false }
        setColor(config, NSSelectorFromString("setOtherIconTintColor:"), custom?.cgColor)
        setName(config, NSSelectorFromString("setIconTintColorName:"), tintName)
        save(config, NSSelectorFromString("save"))
        return true
    }

    private static func fetch() -> NSObject? {
        guard dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) != nil,
              let type = NSClassFromString("SLSIconAppearanceConfiguration") as? NSObject.Type
        else { return nil }
        let selector = NSSelectorFromString("fetchCurrentIconAppearanceConfiguration")
        guard type.responds(to: selector) else { return nil }
        return type.perform(selector)?.takeUnretainedValue() as? NSObject
    }

    /// The tint-name numbering is inferred from SkyLight's string table. When the user
    /// has a named color set, cross-check it against the preference string before
    /// writing, and refuse if this macOS numbers them differently.
    private static func mappingIsVerified(_ config: NSObject) -> Bool {
        guard let name = SystemPreferences.value("AppleIconAppearanceTintColor") as? String,
              let index = tintNames.firstIndex(of: name)
        else { return true }
        let matches = call(config, "iconTintColorName", as: GetU32.self) == UInt32(index + 1)
        if !matches { log.warning("Unrecognized icon tint numbering; not changing folder color") }
        return matches
    }

    private static func function<T>(_ object: NSObject, _ name: String, as type: T.Type) -> T? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return nil }
        return unsafeBitCast(object.method(for: selector), to: type)
    }

    private static func call(_ object: NSObject, _ name: String, as type: GetU32.Type) -> UInt32? {
        function(object, name, as: type).map { $0(object, NSSelectorFromString(name)) }
    }

    private static func call(_ object: NSObject, _ name: String, as type: GetColor.Type) -> Unmanaged<CGColor>? {
        function(object, name, as: type).flatMap { $0(object, NSSelectorFromString(name)) }
    }
}
