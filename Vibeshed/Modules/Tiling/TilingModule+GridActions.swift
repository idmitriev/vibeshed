import AppKit

/// Grid actions on the focused window (attach, attach all, detach, directional
/// move) plus the auto-tile and focus-border toggles.
extension TilingModule {
    func makeAttachAction(mgr: TilingManager, cfg: TilingConfig) -> TilingAction {
        TilingAction(
            id: ActionID(module: "tiling", name: "attach"),
            title: "Attach Window to Grid",
            subtitle: "Snap the focused window into its nearest grid region",
            iconName: "square.grid.3x2.fill",
            keywords: ["tiling", "grid", "attach", "snap"]
        ) { [weak self] _ in
            guard let focused = await MainActor.run(body: { mgr.getFocusedWindow() }) else {
                return .showResult(title: "No Window", body: "No focused window found")
            }
            guard let resolved = await MainActor.run(body: {
                mgr.resolveGrid(for: focused.frame, config: cfg)
            }) else {
                return .showResult(title: "No Grid", body: "No grid configured for this display")
            }
            let cell = TilingGrid.nearestCell(for: focused.frame, in: resolved.area, grid: resolved.grid)
            let frame = TilingGrid.cellRect(
                row: cell.row, col: cell.col, in: resolved.area, grid: resolved.grid, gap: resolved.gap
            )
            try mgr.setFrame(focused, frame: frame)
            await self?.setAssignment(
                windowID: focused.id, displayKey: resolved.displayKey, row: cell.row, col: cell.col
            )
            return .dismiss
        }
    }

    func makeAttachAllAction(mgr: TilingManager) -> TilingAction {
        TilingAction(
            id: ActionID(module: "tiling", name: "attachAll"),
            title: "Attach All Windows to Grid",
            subtitle: "Snap every open window into its display's grid",
            iconName: "square.stack.3d.up.fill",
            keywords: ["tiling", "grid", "attach", "all", "snap"]
        ) { [weak self] _ in
            let windows = await MainActor.run { mgr.listWindows(includeMinimized: false) }
            guard !windows.isEmpty else {
                return .showResult(title: "No Windows", body: "No open windows to attach")
            }
            await self?.runAutoTile(reason: "manual: attachAll")
            return .dismiss
        }
    }

    func makeToggleAutoTileAction() -> TilingAction {
        let enabled = autoTileEnabled
        return TilingAction(
            id: ActionID(module: "tiling", name: "toggleAutoTile"),
            title: enabled ? "Disable Auto-Tile" : "Enable Auto-Tile",
            subtitle: enabled
                ? "Stop automatically tiling windows"
                : "Automatically tile new, moved, and resized windows",
            iconName: enabled ? "xmark.circle" : "wand.and.stars",
            keywords: ["tiling", "grid", "auto", "toggle", "enable", "disable", "start", "stop"]
        ) { [weak self] _ in
            await self?.toggleAutoTile()
            return .dismiss
        }
    }

    func makeToggleFocusBorderAction() -> TilingAction {
        let enabled = focusBorderEnabled
        return TilingAction(
            id: ActionID(module: "tiling", name: "toggleFocusBorder"),
            title: enabled ? "Disable Focus Border" : "Enable Focus Border",
            subtitle: enabled
                ? "Stop drawing the focus border"
                : "Draw a contrast border around the focused tiled window",
            iconName: enabled ? "xmark.circle" : "viewfinder",
            keywords: ["tiling", "grid", "border", "highlight", "focus", "toggle", "enable", "disable"]
        ) { [weak self] _ in
            await self?.toggleFocusBorder()
            return .dismiss
        }
    }

    func makeDetachAction(mgr: TilingManager) -> TilingAction {
        TilingAction(
            id: ActionID(module: "tiling", name: "detach"),
            title: "Detach Window from Grid",
            subtitle: "Stop grid-managing the focused window",
            iconName: "square.dashed",
            keywords: ["tiling", "grid", "detach", "float", "release"]
        ) { [weak self] _ in
            guard let focused = await MainActor.run(body: { mgr.getFocusedWindow() }) else {
                return .showResult(title: "No Window", body: "No focused window found")
            }
            await self?.removeAssignment(windowID: focused.id)
            return .dismiss
        }
    }

    func makeMoveAction(direction: GridDirection, mgr: TilingManager, cfg: TilingConfig) -> TilingAction {
        let (name, title, icon): (String, String, String) = switch direction {
        case .left: ("moveLeft", "Move Window Left", "arrow.left.square")
        case .right: ("moveRight", "Move Window Right", "arrow.right.square")
        case .up: ("moveUp", "Move Window Up", "arrow.up.square")
        case .down: ("moveDown", "Move Window Down", "arrow.down.square")
        }
        return TilingAction(
            id: ActionID(module: "tiling", name: name),
            title: title,
            subtitle: "Move the focused window to the \(direction.rawValue) grid region",
            iconName: icon,
            keywords: ["tiling", "grid", "move", direction.rawValue]
        ) { [weak self] _ in
            guard let focused = await MainActor.run(body: { mgr.getFocusedWindow() }) else {
                return .showResult(title: "No Window", body: "No focused window found")
            }
            guard let resolved = await MainActor.run(body: {
                mgr.resolveGrid(for: focused.frame, config: cfg)
            }) else {
                return .showResult(title: "No Grid", body: "No grid configured for this display")
            }
            // Always derive the current cell from the window's live frame (not a stored
            // assignment) so moves stay correct even if something else — window/cycle*,
            // a manual drag, another tool — repositioned the window since the last tiling
            // action.
            let currentCell = TilingGrid.nearestCell(for: focused.frame, in: resolved.area, grid: resolved.grid)
            guard let nextCell = TilingGrid.neighborCell(
                from: currentCell, direction: direction, grid: resolved.grid
            ) else {
                return .dismiss
            }
            let frame = TilingGrid.cellRect(
                row: nextCell.row, col: nextCell.col, in: resolved.area, grid: resolved.grid, gap: resolved.gap
            )
            try mgr.setFrame(focused, frame: frame)
            await self?.setAssignment(
                windowID: focused.id, displayKey: resolved.displayKey, row: nextCell.row, col: nextCell.col
            )
            return .dismiss
        }
    }
}
