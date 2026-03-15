import AppKit
import SwiftUI

@MainActor
@Observable
final class ThemeEngine {
    private(set) var theme: VibeTheme = .default

    private let eventBus: EventBus
    private var lastArtworkURL: String?
    private var artworkColors: (dominant: NSColor, vibrant: NSColor)?
    private var screenColors: (dominant: NSColor, vibrant: NSColor)?

    init(eventBus: EventBus) {
        self.eventBus = eventBus
    }

    func start() {
        recompute()
    }

    /// Called when the picker opens. Gathers signals and recomputes theme.
    func refresh(context: SystemContext) async {
        if context.isSpotifyRunning {
            await refreshMusicColors()
        } else {
            artworkColors = nil
            lastArtworkURL = nil
        }

        refreshScreenColors()
        recompute(context: context)
    }

    // MARK: - Music Color Extraction

    private func refreshMusicColors() async {
        do {
            guard let nowPlaying = try await SpotifyManager.nowPlaying(),
                  nowPlaying.isPlaying,
                  !nowPlaying.artworkURL.isEmpty
            else {
                artworkColors = nil
                lastArtworkURL = nil
                return
            }

            if nowPlaying.artworkURL == lastArtworkURL, artworkColors != nil {
                return
            }

            lastArtworkURL = nowPlaying.artworkURL
            artworkColors = await ColorExtractor.extractColors(
                from: nowPlaying.artworkURL
            )
        } catch {
            artworkColors = nil
            lastArtworkURL = nil
        }
    }

    // MARK: - Screen Color Extraction

    private func refreshScreenColors() {
        // Try full-screen capture (requires Screen Recording permission)
        if let displayImage = CGDisplayCreateImage(CGMainDisplayID()) {
            screenColors = ColorExtractor.extractColors(from: displayImage)
            return
        }

        // Fallback: desktop wallpaper (no permission needed)
        screenColors = extractWallpaperColors()
    }

    private func extractWallpaperColors() -> (dominant: NSColor, vibrant: NSColor)? {
        guard let screen = NSScreen.main,
              let wallpaperURL = NSWorkspace.shared.desktopImageURL(
                  for: screen
              ),
              let image = NSImage(contentsOf: wallpaperURL),
              let cgImage = image.cgImage(
                  forProposedRect: nil, context: nil, hints: nil
              )
        else { return nil }

        return ColorExtractor.extractColors(from: cgImage)
    }

    // MARK: - Theme Computation

    private func recompute(context: SystemContext? = nil) {
        let source = resolveSourceColor(context: context)
        let adjusted = applyTimeOfDay(source, hour: context?.hour)
        setTheme(buildTheme(from: adjusted))
    }

    private func resolveSourceColor(context: SystemContext?) -> NSColor {
        if let colors = artworkColors {
            return colors.vibrant
        }
        if let colors = screenColors {
            return colors.vibrant
        }
        return timeOfDayBaseColor(hour: context?.hour ?? currentHour())
    }

    private func buildTheme(from source: NSColor) -> VibeTheme {
        let color = Color(nsColor: source)

        return VibeTheme(
            accent: color,
            backgroundTint: color.opacity(0.06),
            selectionHighlight: color.opacity(0.12),
            searchHighlight: color,
            iconTint: color.opacity(0.7),
            shadowColor: color.opacity(0.3)
        )
    }

    private func setTheme(_ newTheme: VibeTheme) {
        guard newTheme != theme else { return }
        withAnimation(.easeInOut(duration: 0.5)) {
            theme = newTheme
        }
    }

    // MARK: - Time-of-Day Color

    private func timeOfDayBaseColor(hour: Int) -> NSColor {
        if hour >= 20 || hour < 5 {
            // Night: warm amber
            return NSColor(red: 0.9, green: 0.6, blue: 0.3, alpha: 1)
        } else if hour >= 5, hour < 8 {
            // Early morning: cool blue
            return NSColor(red: 0.3, green: 0.5, blue: 0.8, alpha: 1)
        } else {
            // Daytime: neutral system accent
            return NSColor.controlAccentColor
        }
    }

    private func applyTimeOfDay(_ color: NSColor, hour: Int?) -> NSColor {
        guard let hour else { return color }

        let warmth: Double
        if hour >= 20 || hour < 5 {
            warmth = 0.08
        } else if hour >= 5, hour < 8 {
            warmth = -0.05
        } else {
            return color
        }

        guard let rgbColor = color.usingColorSpace(.deviceRGB) else {
            return color
        }

        let red = min(1, max(0, rgbColor.redComponent + warmth))
        let green = rgbColor.greenComponent
        let blue = min(1, max(0, rgbColor.blueComponent - warmth))

        return NSColor(red: red, green: green, blue: blue, alpha: 1)
    }

    private func currentHour() -> Int {
        Calendar.current.component(.hour, from: Date())
    }
}
