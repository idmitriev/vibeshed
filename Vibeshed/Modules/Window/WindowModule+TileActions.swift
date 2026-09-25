import AppKit

/// Frame functions for one half-screen tile and the half opposite it.
private struct TileFunctions: Sendable {
    let primary: @Sendable (CGRect, PaddingConfig) -> CGRect
    let opposite: @Sendable (CGRect, PaddingConfig) -> CGRect
}

private struct OppositeTileInfo {
    let name: String
    let icon: String
}

/// Half-screen tile actions. Tiling one window offers the other open windows for the
/// opposite half.
extension WindowModule {
    func buildTileActions(mgr: WindowManager, cfg: WindowConfig) -> [WindowAction] {
        [
            makeTileAction(
                meta: WindowActionMetadata(
                    id: "tileLeft", title: "Tile Left Half",
                    subtitle: "Move focused window to left half of screen",
                    icon: "rectangle.lefthalf.filled",
                    keywords: ["tile", "left", "half", "split"]
                ),
                tileFuncs: TileFunctions(primary: WindowSizing.tileLeft, opposite: WindowSizing.tileRight),
                opposite: OppositeTileInfo(name: "Right", icon: "rectangle.righthalf.filled"),
                mgr: mgr, cfg: cfg
            ),
            makeTileAction(
                meta: WindowActionMetadata(
                    id: "tileRight", title: "Tile Right Half",
                    subtitle: "Move focused window to right half of screen",
                    icon: "rectangle.righthalf.filled",
                    keywords: ["tile", "right", "half", "split"]
                ),
                tileFuncs: TileFunctions(primary: WindowSizing.tileRight, opposite: WindowSizing.tileLeft),
                opposite: OppositeTileInfo(name: "Left", icon: "rectangle.lefthalf.filled"),
                mgr: mgr, cfg: cfg
            ),
            makeTileAction(
                meta: WindowActionMetadata(
                    id: "tileTop", title: "Tile Top Half",
                    subtitle: "Move focused window to top half of screen",
                    icon: "rectangle.tophalf.filled",
                    keywords: ["tile", "top", "half", "split"]
                ),
                tileFuncs: TileFunctions(primary: WindowSizing.tileTop, opposite: WindowSizing.tileBottom),
                opposite: OppositeTileInfo(name: "Bottom", icon: "rectangle.bottomhalf.filled"),
                mgr: mgr, cfg: cfg
            ),
            makeTileAction(
                meta: WindowActionMetadata(
                    id: "tileBottom", title: "Tile Bottom Half",
                    subtitle: "Move focused window to bottom half of screen",
                    icon: "rectangle.bottomhalf.filled",
                    keywords: ["tile", "bottom", "half", "split"]
                ),
                tileFuncs: TileFunctions(primary: WindowSizing.tileBottom, opposite: WindowSizing.tileTop),
                opposite: OppositeTileInfo(name: "Top", icon: "rectangle.tophalf.filled"),
                mgr: mgr, cfg: cfg
            ),
        ]
    }

    private func makeTileAction(
        meta: WindowActionMetadata,
        tileFuncs: TileFunctions,
        opposite: OppositeTileInfo,
        mgr: WindowManager, cfg: WindowConfig
    ) -> WindowAction {
        WindowAction(
            id: ActionID(module: "window", name: meta.id),
            title: meta.title, subtitle: meta.subtitle, iconName: meta.icon, keywords: meta.keywords
        ) { _ in
            guard let focused = await MainActor.run(body: { mgr.getFocusedWindow() }) else {
                return .showResult(title: "No Window", body: "No focused window found")
            }
            let newFrame = tileFuncs.primary(focused.screenFrame, cfg.padding)
            try mgr.setFrame(focused, frame: newFrame)

            let windows = await MainActor.run {
                mgr.listWindows(includeMinimized: false)
            }
            let others = windows.filter { $0.id != focused.id }
            guard !others.isEmpty else { return .dismiss }

            let tileActions = others.map { window in
                WindowAction(
                    id: ActionID(module: "window", name: "tile\(opposite.name)For.\(window.id)"),
                    title: "Tile \(opposite.name): \(window.displayLabel)",
                    subtitle: "Move to \(opposite.name.lowercased()) half of screen",
                    iconName: opposite.icon,
                    relevanceScore: 0.9,
                    keywords: ["tile", opposite.name.lowercased()],
                    windowID: window.id,
                    appBundleID: window.bundleID
                ) { _ in
                    let oppFrame = tileFuncs.opposite(focused.screenFrame, cfg.padding)
                    try mgr.setFrame(window, frame: oppFrame)
                    try mgr.focusWindow(window)
                    return .dismiss
                }
            }
            return .pushActions(tileActions)
        }
    }
}
