import AppKit
import CoreGraphics

struct ResolvedGrid {
    let grid: DisplayGridConfig
    let area: CGRect
    let displayKey: String
    let gap: Double
}

struct TilingManager: Sendable {
    private let windowManager = WindowManager()

    @MainActor
    func getFocusedWindow() -> WindowInfo? {
        windowManager.getFocusedWindow()
    }

    @MainActor
    func listWindows(includeMinimized: Bool) -> [WindowInfo] {
        windowManager.listWindows(includeMinimized: includeMinimized)
    }

    func setFrame(_ window: WindowInfo, frame: CGRect) throws {
        try windowManager.setFrame(window, frame: frame)
    }

    func focusWindow(_ window: WindowInfo) throws {
        try windowManager.focusWindow(window)
    }

    func isTileable(_ window: WindowInfo) -> Bool {
        windowManager.isTileable(window)
    }

    /// Resolves the matching `DisplayGridConfig` and usable CG-coordinate area for a window's
    /// frame, based on which physical display it's on. Returns nil if no display or grid
    /// (explicit or default) could be resolved.
    @MainActor
    func resolveGrid(for frame: CGRect, config: TilingConfig) -> ResolvedGrid? {
        guard let screen = WindowListHelper.screen(forFrame: frame) else { return nil }
        // `keys` is already most-specific-first (name, then "main", then index). Resolve by
        // walking keys in that order rather than `config.displays` in config-file order, so a
        // more specific match (e.g. an exact display name) always wins over a broader one
        // (e.g. "main") even when both match the same physical screen and "main" happens to
        // be listed first in the config.
        let keys = WindowListHelper.candidateMatchKeys(for: screen)
        let matchedGrid = keys.lazy.compactMap { key in
            config.displays.first(where: { $0.match == key })
        }.first
        guard let grid = matchedGrid ?? config.defaultGrid else {
            return nil
        }
        let screenFrame = WindowSizing.visibleFrameCG(of: screen)
        let effectivePadding = grid.padding ?? config.padding
        let area = WindowSizing.usableArea(screenFrame: screenFrame, padding: effectivePadding)
        return ResolvedGrid(grid: grid, area: area, displayKey: keys.first ?? "unknown", gap: effectivePadding.gap)
    }
}
