import AppKit

enum AppColorMap {
    private static let map: [String: NSColor] = [
        // Apple
        "com.apple.dt.Xcode": .systemBlue,
        "com.apple.Terminal": NSColor(
            red: 0.3, green: 0.3, blue: 0.35, alpha: 1
        ),
        "com.apple.Safari": .systemBlue,
        "com.apple.finder": .systemBlue,
        "com.apple.MobileSMS": NSColor(
            red: 0.2, green: 0.78, blue: 0.35, alpha: 1
        ),
        "com.apple.mail": .systemBlue,
        "com.apple.Music": NSColor(
            red: 0.98, green: 0.18, blue: 0.35, alpha: 1
        ),

        // Browsers
        "com.google.Chrome": NSColor(
            red: 0.26, green: 0.52, blue: 0.96, alpha: 1
        ),
        "com.brave.Browser": NSColor(
            red: 1.0, green: 0.35, blue: 0.0, alpha: 1
        ),

        // Dev tools
        "com.microsoft.VSCode": .systemBlue,
        "com.googlecode.iterm2": NSColor(
            red: 0.2, green: 0.8, blue: 0.3, alpha: 1
        ),

        // Media & comm
        "com.spotify.client": NSColor(
            red: 0.12, green: 0.84, blue: 0.38, alpha: 1
        ),
        "com.tinyspeck.slackmacgap": NSColor(
            red: 0.38, green: 0.15, blue: 0.56, alpha: 1
        ),
        "com.figma.Desktop": NSColor(
            red: 0.64, green: 0.33, blue: 1.0, alpha: 1
        ),
        "ru.keepcoder.Telegram": NSColor(
            red: 0.2, green: 0.6, blue: 0.86, alpha: 1
        ),
        "md.obsidian": NSColor(
            red: 0.49, green: 0.36, blue: 0.85, alpha: 1
        ),
    ]

    /// Prefixes for VSCode-family editors that all map to blue.
    private static let vscodeVariantPrefixes = [
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92",
        "com.exafunction.windsurf",
    ]

    static func color(for bundleID: String) -> NSColor? {
        if let color = map[bundleID] { return color }
        for prefix in vscodeVariantPrefixes where bundleID.hasPrefix(prefix) {
            return .systemBlue
        }
        return nil
    }
}
