import AppKit
import SwiftUI

@MainActor
@Observable
final class ThemeEngine {
    private(set) var theme: VibeTheme = .default

    private let eventBus: EventBus
    private var intensity: Double = 0
    private var lastArtworkURL: String?
    private var artworkColors: (dominant: NSColor, vibrant: NSColor)?
    private var screenColors: (dominant: NSColor, vibrant: NSColor)?
    private var eventSubscriptionID: UUID?

    init(eventBus: EventBus) {
        self.eventBus = eventBus
    }

    func start(intensity: Double) {
        self.intensity = max(0, min(1, intensity))
        listenForConfigReloads()
        recompute()
    }

    func updateIntensity(_ newIntensity: Double) {
        let clamped = max(0, min(1, newIntensity))
        guard clamped != intensity else { return }
        intensity = clamped
        recompute()
    }

    /// Called when the picker opens. Gathers signals and recomputes theme.
    func refresh(context: SystemContext) async {
        guard intensity > 0 else {
            theme = .default
            return
        }

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
        guard intensity > 0 else {
            setTheme(.default)
            return
        }

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

        let bgTintFactor = intensity > 0.3
            ? lerp(0, 0.06, t: (intensity - 0.3) / 0.7)
            : 0.0

        let glowFactor = intensity > 0.8
            ? lerp(0, 0.4, t: (intensity - 0.8) / 0.2)
            : 0.0

        let shadowFactor = intensity > 0.8
            ? lerp(0, 0.3, t: (intensity - 0.8) / 0.2)
            : 0.0

        return VibeTheme(
            accent: color,
            backgroundTint: bgTintFactor > 0
                ? color.opacity(bgTintFactor) : nil,
            selectionHighlight: color.opacity(0.08 + intensity * 0.04),
            searchHighlight: color,
            iconTint: intensity > 0.6
                ? color.opacity(0.7) : nil,
            borderGlow: glowFactor > 0
                ? color.opacity(glowFactor) : nil,
            shadowColor: shadowFactor > 0
                ? color.opacity(shadowFactor) : nil,
            intensity: intensity
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

    // MARK: - Config Reload Listener

    private func listenForConfigReloads() {
        Task { [weak self] in
            guard let self else { return }
            let (id, stream) = await eventBus.subscribe()
            eventSubscriptionID = id
            for await event in stream {
                if case .configReloaded = event {
                    // Intensity may have changed — caller should
                    // call updateIntensity with new config value.
                    break
                }
            }
        }
    }

    // MARK: - Helpers

    private func lerp(
        _ from: Double, _ to: Double, t factor: Double
    ) -> Double {
        from + (to - from) * max(0, min(1, factor))
    }
}
