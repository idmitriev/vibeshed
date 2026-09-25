import AppKit
import CoreGraphics
import OSLog
import SwiftUI

actor TilingModule: ModuleConfigurable {
    let id = "tiling"
    let displayName = "Tiling"
    let iconName = "square.grid.3x2"
    var isEnabled = true

    typealias Config = TilingConfig
    static var defaultConfig: Config? {
        .defaultValue
    }

    static var requiredPermissions: Set<Permission> {
        [.accessibility]
    }

    private var config: TilingConfig = .defaultValue
    private let manager = TilingManager()
    private var assignments: [Int: GridAssignment] = [:]
    private let log = Log.module("tiling")

    /// Runtime-only; always starts disabled on launch and is toggled via
    /// `tiling/toggleAutoTile` — not persisted config.
    private var autoTileEnabled = false
    private var seenWindowIDs: Set<Int> = []
    private var lastKnownFrames: [Int: CGRect] = [:]
    private var pollTask: Task<Void, Never>?

    /// Runtime-only; always starts disabled on launch and is toggled via
    /// `tiling/toggleFocusBorder` — not persisted config.
    private var focusBorderEnabled = false
    private var focusBorderPollTask: Task<Void, Never>?

    func initialize(context: ModuleContext) async throws {
        // Seed seen-window/frame state from what's already open so the poller (below)
        // only reacts to windows/moves that appear after auto-tile is enabled.
        let existing = await MainActor.run { manager.listWindows(includeMinimized: false) }
        seenWindowIDs = Set(existing.map(\.id))
        lastKnownFrames = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0.frame) })
        startPolling()
        startFocusBorderPolling()
        log.info("Tiling module initialized")
    }

    func teardown() async {
        pollTask?.cancel()
        pollTask = nil
        focusBorderPollTask?.cancel()
        focusBorderPollTask = nil
        await FocusBorderController.shared.hide()
    }

    func configDidUpdate(_ config: TilingConfig) async {
        self.config = config
        log.debug("Config updated: \(config.displays.count, privacy: .public) display grid(s)")
    }

    static func validate(_ config: TilingConfig) -> ConfigValidationResult {
        var errors: [String] = []
        var seenMatches: Set<String> = []
        for grid in config.displays {
            guard let match = grid.match, !match.isEmpty else {
                errors.append("displays[].match must not be empty")
                continue
            }
            if seenMatches.contains(match) {
                errors.append("duplicate displays[].match value: \(match)")
            }
            seenMatches.insert(match)
            errors.append(contentsOf: validateGrid(grid, label: "displays[\(match)]"))
        }
        if let defaultGrid = config.defaultGrid {
            errors.append(contentsOf: validateGrid(defaultGrid, label: "defaultGrid"))
        }
        if config.padding.top < 0 || config.padding.bottom < 0
            || config.padding.left < 0 || config.padding.right < 0
        {
            errors.append("Padding values must be non-negative")
        }
        if config.padding.gap < 0 {
            errors.append("Gap must be non-negative")
        }
        if config.autoTile.pollingInterval <= 0 {
            errors.append("autoTile.pollingInterval must be positive")
        }
        if config.autoTile.minimumSize < 0 {
            errors.append("autoTile.minimumSize must be non-negative")
        }
        if let focusBorder = config.focusBorder {
            if focusBorder.width <= 0 {
                errors.append("focusBorder.width must be positive")
            }
            if focusBorder.cornerRadius < 0 {
                errors.append("focusBorder.cornerRadius must be non-negative")
            }
            if focusBorder.pollingInterval <= 0 {
                errors.append("focusBorder.pollingInterval must be positive")
            }
        }
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    private static func validateGrid(_ grid: DisplayGridConfig, label: String) -> [String] {
        var errors: [String] = []
        if grid.columns.isEmpty {
            errors.append("\(label).columns must not be empty")
        }
        if grid.rows.isEmpty {
            errors.append("\(label).rows must not be empty")
        }
        if grid.columns.contains(where: { $0 <= 0 }) {
            errors.append("\(label).columns values must be positive")
        }
        if grid.rows.contains(where: { $0 <= 0 }) {
            errors.append("\(label).rows values must be positive")
        }
        return errors
    }

    func provideActions(query: String, scoring: ScoringContext) async -> [any Action] {
        buildActions()
    }

    /// Options for `detachWindow`: only windows currently tracked as tiled (having a grid
    /// assignment) — detaching an unmanaged window would be a no-op. The picker applies
    /// fuzzy filtering on the query itself.
    func provideParameterOptions(
        for parameterID: String,
        in actionID: ActionID,
        query: String
    ) async -> [ParameterOption] {
        guard parameterID == "window", actionID.actionName == "detachWindow" else { return [] }
        let tiledIDs = Set(assignments.keys)
        guard !tiledIDs.isEmpty else { return [] }
        let mgr = manager
        let windows = await MainActor.run {
            mgr.listWindows(includeMinimized: false).filter { tiledIDs.contains($0.id) }
        }
        return windows.map { window in
            let appURL = window.bundleID.flatMap {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
            }
            return ParameterOption(
                id: String(window.id),
                label: window.displayLabel,
                iconName: "macwindow",
                iconURL: appURL
            )
        }
    }

    // MARK: - Build Actions

    private func buildActions() -> [TilingAction] {
        let mgr = manager
        let cfg = config

        var actions: [TilingAction] = [
            makeAttachAction(mgr: mgr, cfg: cfg),
            makeAttachAllAction(mgr: mgr),
            makeDetachAction(mgr: mgr),
            makeDetachWindowAction(),
            makeSwapNextSplitAction(mgr: mgr, cfg: cfg),
            makeFocusSplitAction(forward: true, mgr: mgr, cfg: cfg),
            makeFocusSplitAction(forward: false, mgr: mgr, cfg: cfg),
            makeMoveAction(direction: .left, mgr: mgr, cfg: cfg),
            makeMoveAction(direction: .right, mgr: mgr, cfg: cfg),
            makeMoveAction(direction: .up, mgr: mgr, cfg: cfg),
            makeMoveAction(direction: .down, mgr: mgr, cfg: cfg),
            makeToggleAutoTileAction(),
            makeToggleFocusBorderAction(),
        ]
        if let enabled = cfg.enabledActions {
            actions = actions.filter { enabled.contains($0.id.actionName) }
        }
        return actions
    }

    private func makeAttachAction(mgr: TilingManager, cfg: TilingConfig) -> TilingAction {
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

    private func makeAttachAllAction(mgr: TilingManager) -> TilingAction {
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

    private func makeToggleAutoTileAction() -> TilingAction {
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

    private func makeToggleFocusBorderAction() -> TilingAction {
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

    private func makeDetachAction(mgr: TilingManager) -> TilingAction {
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

    private func makeMoveAction(direction: GridDirection, mgr: TilingManager, cfg: TilingConfig) -> TilingAction {
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
            guard let nextCell = TilingGrid.neighborCell(from: currentCell, direction: direction, grid: resolved.grid) else {
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

    // MARK: - Auto Tile

    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = await self.config.autoTile.pollingInterval
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await self.pollForNewWindows()
            }
        }
    }

    private func pollForNewWindows() async {
        guard autoTileEnabled else { return }

        let windows = await MainActor.run { manager.listWindows(includeMinimized: false) }
        // While the left mouse button is physically held down, a move/resize in
        // progress is very likely a live drag — don't act on it, and don't update
        // lastKnownFrames either, so it stays pinned to the pre-drag position. Once
        // the button is released, the next tick compares the final (dropped) frame
        // against that pre-drag baseline, is guaranteed to see a difference, and
        // tiles exactly once — instead of yanking the window mid-drag on every tick.
        let dragging = Self.isLeftMouseButtonDown()

        let newWindows = windows.filter { !seenWindowIDs.contains($0.id) }
        for window in newWindows {
            await autoTileIfEligible(window)
        }
        if !dragging {
            let moved = windows.filter { window in
                seenWindowIDs.contains(window.id)
                    && !Self.framesRoughlyEqual(lastKnownFrames[window.id], window.frame)
            }
            for window in moved {
                // .nearest, not .nextOpen: the window already had a place in the grid and
                // was just dropped somewhere else — snap to whichever cell it was actually
                // dropped near, not to some arbitrary open slot (which could easily be its
                // own former cell, undoing the move the user just made).
                await autoTileIfEligible(window, placement: .nearest)
            }
        }

        seenWindowIDs = Set(windows.map(\.id))
        if !dragging {
            lastKnownFrames = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.frame) })
        }
    }

    private func toggleAutoTile() async {
        if autoTileEnabled {
            disableAutoTile()
        } else {
            await enableAutoTile()
        }
    }

    private func enableAutoTile() async {
        guard !autoTileEnabled else { return }
        autoTileEnabled = true
        // Reseed tracking state to "now" so the next poll tick doesn't treat every
        // window as newly-created/moved just because auto-tile was off for a while.
        let existing = await MainActor.run { manager.listWindows(includeMinimized: false) }
        seenWindowIDs = Set(existing.map(\.id))
        lastKnownFrames = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0.frame) })
        await runAutoTile(reason: "enabled")
    }

    private func disableAutoTile() {
        autoTileEnabled = false
    }

    // MARK: - Focus Border

    private func startFocusBorderPolling() {
        focusBorderPollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = await self.config.focusBorder?.pollingInterval ?? 0.15
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await self.pollFocusBorder()
            }
        }
    }

    /// Shows the border around the focused window if (and only if) it's currently tracked
    /// as tiled (has a grid `assignments` entry) — independent of `autoTileEnabled`, so a
    /// window manually attached earlier still gets a border even with auto-tile off.
    private func pollFocusBorder() async {
        guard focusBorderEnabled else { return }
        // While Mission Control, App Exposé, or a space-switch/fullscreen transition is
        // active, every real window scatters or shrinks to a thumbnail — but still reports
        // its normal frame via AX, so the border would float in its old, now-meaningless
        // position. There is no public "Mission Control is active" signal (the frontmost
        // app does NOT change to the Dock on modern macOS), so instead verify the focused
        // window is actually on screen at its AX-reported frame; if it isn't where it
        // claims to be, hide the border for the duration.
        let (focused, missionControlActive) = await MainActor.run {
            (
                manager.getFocusedWindow(),
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.dock"
            )
        }
        guard !missionControlActive, let focused, assignments[focused.id] != nil,
              Self.windowIsAtItsFrame(focused)
        else {
            await FocusBorderController.shared.hide()
            return
        }
        let borderConfig = config.focusBorder ?? FocusBorderConfig()
        await FocusBorderController.shared.show(
            cgFrame: focused.frame,
            width: borderConfig.width,
            cornerRadius: borderConfig.cornerRadius
        )
    }

    private func toggleFocusBorder() async {
        if focusBorderEnabled {
            await disableFocusBorder()
        } else {
            await enableFocusBorder()
        }
    }

    private func enableFocusBorder() async {
        guard !focusBorderEnabled else { return }
        focusBorderEnabled = true
        await pollFocusBorder()
    }

    private func disableFocusBorder() async {
        guard focusBorderEnabled else { return }
        focusBorderEnabled = false
        await FocusBorderController.shared.hide()
    }

    private static func isLeftMouseButtonDown() -> Bool {
        CGEventSource.buttonState(.combinedSessionState, button: .left)
    }

    /// True if the window is currently on screen at (roughly) the frame AX reports for it.
    /// False while the window is scattered by Mission Control/App Exposé, sits on another
    /// space, or is otherwise not rendered where AX claims — all states where drawing the
    /// border at the AX frame would put it in the wrong place.
    private static func windowIsAtItsFrame(_ window: WindowInfo, tolerance: Double = 2.0) -> Bool {
        guard let onScreen = WindowListHelper.onScreenBounds(of: window.id) else { return false }
        return abs(onScreen.origin.x - window.frame.origin.x) <= tolerance
            && abs(onScreen.origin.y - window.frame.origin.y) <= tolerance
            && abs(onScreen.width - window.frame.width) <= tolerance
            && abs(onScreen.height - window.frame.height) <= tolerance
    }

    private static func framesRoughlyEqual(_ previous: CGRect?, _ current: CGRect, tolerance: Double = 1.0) -> Bool {
        guard let previous else { return false }
        return abs(previous.origin.x - current.origin.x) <= tolerance
            && abs(previous.origin.y - current.origin.y) <= tolerance
            && abs(previous.width - current.width) <= tolerance
            && abs(previous.height - current.height) <= tolerance
    }

    private func runAutoTile(reason: String) async {
        let windows = await MainActor.run { manager.listWindows(includeMinimized: false) }
        log.info("Auto-tiling on \(reason, privacy: .public): \(windows.count, privacy: .public) window(s)")
        for window in windows {
            await autoTileIfEligible(window)
        }
    }

    /// `.nextOpen` picks the first free cell in row-major order — right for a window with
    /// no established position (a brand-new window, or startup/attachAll bulk placement).
    /// `.nearest` snaps to whichever cell the window's current frame is geometrically
    /// closest to — right for a window that already had a place and was just moved/resized,
    /// where the drop position itself expresses where the user wants it.
    private enum CellPlacementStrategy {
        case nextOpen
        case nearest
    }

    private func autoTileIfEligible(_ window: WindowInfo, placement: CellPlacementStrategy = .nextOpen) async {
        let cfg = config
        if let bundleID = window.bundleID, cfg.autoTile.excludedBundleIDs.contains(bundleID) {
            return
        }
        // Filter out tooltips, HUDs, panels, and other non-standard/fixed-size windows
        // that shouldn't be forced into a grid cell.
        if window.frame.width < cfg.autoTile.minimumSize || window.frame.height < cfg.autoTile.minimumSize {
            return
        }
        guard manager.isTileable(window) else { return }
        guard let resolved = await MainActor.run(body: {
            manager.resolveGrid(for: window.frame, config: cfg)
        }) else {
            return
        }
        // Already sitting in a grid cell (within tolerance) — leave it alone. Just refresh
        // its occupancy record so a subsequent unaligned window doesn't get placed on top
        // of it. Without this check, re-running attachAll/auto-tile would needlessly
        // reposition every window on every call.
        let aligned = TilingGrid.matchingCell(
            for: window.frame, in: resolved.area, grid: resolved.grid, gap: resolved.gap
        )
        if let aligned {
            setAssignment(windowID: window.id, displayKey: resolved.displayKey, row: aligned.row, col: aligned.col)
            return
        }
        let cell: (row: Int, col: Int) = switch placement {
        case .nextOpen:
            nextOpenCell(for: window.id, displayKey: resolved.displayKey, grid: resolved.grid)
        case .nearest:
            TilingGrid.nearestCell(for: window.frame, in: resolved.area, grid: resolved.grid)
        }
        let frame = TilingGrid.cellRect(
            row: cell.row, col: cell.col, in: resolved.area, grid: resolved.grid, gap: resolved.gap
        )
        do {
            try manager.setFrame(window, frame: frame)
            setAssignment(windowID: window.id, displayKey: resolved.displayKey, row: cell.row, col: cell.col)
        } catch {
            log.error("autoTile: failed to set frame for window \(window.id, privacy: .public)")
        }
    }

    /// First grid cell (row-major order) not already occupied by a tracked assignment on
    /// this display; wraps back to (0, 0) if every cell is already taken (overlap allowed,
    /// consistent with the manual move actions' collision policy). Excludes `windowID`'s own
    /// prior assignment from the occupied set — otherwise a window that resizes itself
    /// slightly (e.g. System Settings switching panes) and no longer exactly matches its own
    /// cell would see that cell as "taken" and get bounced to a different one, then bounce
    /// back next time, oscillating between cells forever.
    private func nextOpenCell(for windowID: Int, displayKey: String, grid: DisplayGridConfig) -> (row: Int, col: Int) {
        let occupied = Set(
            assignments
                .filter { $0.key != windowID && $0.value.displayKey == displayKey }
                .values
                .map { $0.row * grid.columns.count + $0.col }
        )
        for row in 0 ..< grid.rows.count {
            for col in 0 ..< grid.columns.count where !occupied.contains(row * grid.columns.count + col) {
                return (row: row, col: col)
            }
        }
        return (row: 0, col: 0)
    }

    // MARK: - Assignment State

    // Internal (not private): also called from the split-navigation actions in
    // TilingModule+SplitActions.swift.
    func setAssignment(windowID: Int, displayKey: String, row: Int, col: Int) {
        assignments[windowID] = GridAssignment(displayKey: displayKey, row: row, col: col)
    }

    func removeAssignment(windowID: Int) {
        assignments.removeValue(forKey: windowID)
    }
}

private struct GridAssignment {
    let displayKey: String
    var row: Int
    var col: Int
}
