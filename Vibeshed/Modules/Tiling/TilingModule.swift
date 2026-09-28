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
    private(set) var autoTileEnabled = false
    /// On-screen windows `TilingManager.isTileable` said yes to, so a display's layout pass
    /// doesn't ask each app over AX again (a busy app blocks AX calls for seconds).
    private var tileable: Set<Int> = []
    private var lastKnownFrames: [Int: CGRect] = [:]
    private var pollTask: Task<Void, Never>?

    /// Runtime-only; always starts disabled on launch and is toggled via
    /// `tiling/toggleFocusBorder` — not persisted config.
    private(set) var focusBorderEnabled = false
    private var focusBorderPollTask: Task<Void, Never>?

    func initialize(context: ModuleContext) async throws {
        // Seed seen-window/frame state from what's already open so the poller (below)
        // only reacts to windows/moves that appear after auto-tile is enabled.
        let existing = await MainActor.run { manager.listWindows(includeMinimized: false) }
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
        var errors = validateGrids(config)
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
            errors.append(contentsOf: validateFocusBorder(focusBorder))
        }
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    /// Per-display grids (unique, non-empty `match`) and the default grid.
    private static func validateGrids(_ config: TilingConfig) -> [String] {
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
        return errors
    }

    private static func validateFocusBorder(_ focusBorder: FocusBorderConfig) -> [String] {
        var errors: [String] = []
        if focusBorder.width <= 0 {
            errors.append("focusBorder.width must be positive")
        }
        if focusBorder.cornerRadius < 0 {
            errors.append("focusBorder.cornerRadius must be non-negative")
        }
        if focusBorder.pollingInterval <= 0 {
            errors.append("focusBorder.pollingInterval must be positive")
        }
        return errors
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
        // While the left mouse button is physically held down, a window is very likely
        // being dragged or resized (or a tab torn off into a new window). Act on nothing
        // and keep the pre-drag baseline: once the button is released, the next tick sees
        // the whole change against it and tiles exactly once, instead of yanking a window
        // mid-drag.
        guard !Self.isLeftMouseButtonDown() else { return }

        let windows = await MainActor.run { manager.listWindows(includeMinimized: false) }
        let previousFrames = lastKnownFrames
        lastKnownFrames = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.frame) })
        tileable.formIntersection(lastKnownFrames.keys)
        await layOutChanges(in: windows, since: previousFrames)
    }

    /// Internal (not private), as are `toggleFocusBorder` and `runAutoTile`: called
    /// from the actions in TilingModule+GridActions.swift.
    func toggleAutoTile() async {
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
        tileable = []
        lastKnownFrames = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0.frame) })
        await runAutoTile(reason: "enabled")
    }

    private func disableAutoTile() {
        autoTileEnabled = false
    }
}

// MARK: - Focus Border

extension TilingModule {
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

    func toggleFocusBorder() async {
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

    func runAutoTile(reason: String) async {
        let windows = await MainActor.run { manager.listWindows(includeMinimized: false) }
        log.info("Auto-tiling on \(reason, privacy: .public): \(windows.count, privacy: .public) window(s)")
        tileable.formIntersection(windows.map(\.id))
        await layOut(windows) { _ in .arrived }
    }

    /// Lays out the displays touched since the last poll: where windows appeared or moved
    /// to, and where moved or vanished (closed, minimized, hidden) windows were — a display
    /// left with one window maximizes it, one that gains a second goes back to the grid.
    private func layOutChanges(in windows: [WindowInfo], since previousFrames: [Int: CGRect]) async {
        let appeared = Set(windows.filter { previousFrames[$0.id] == nil }.map(\.id))
        let moved = Set(windows.filter { window in
            previousFrames[window.id] != nil && !Self.framesRoughlyEqual(previousFrames[window.id], window.frame)
        }.map(\.id))
        let vanished = Set(previousFrames.keys).subtracting(windows.map(\.id))
        guard !appeared.isEmpty || !moved.isEmpty || !vanished.isEmpty else { return }

        let touchedFrames = windows.filter { appeared.contains($0.id) || moved.contains($0.id) }.map(\.frame)
            + moved.union(vanished).compactMap { previousFrames[$0] }
        let cfg = config
        let mgr = manager
        let touched = await MainActor.run {
            Set(touchedFrames.compactMap { mgr.resolveGrid(for: $0, config: cfg)?.displayKey })
        }
        await layOut(windows, displays: touched) { window in
            if appeared.contains(window.id) { return .arrived }
            return moved.contains(window.id) ? .moved : .unchanged
        }
    }

    /// Plans each display's eligible windows with `AutoTileLayout` — only the displays in
    /// `displayKeys`, or every display with a grid when nil — and applies the result.
    private func layOut(
        _ windows: [WindowInfo],
        displays displayKeys: Set<String>? = nil,
        reason: (WindowInfo) -> AutoTileLayout.Reason
    ) async {
        let cfg = config
        let mgr = manager
        let displays = await MainActor.run { mgr.windowsByDisplay(windows, config: cfg) }
        for display in displays where displayKeys?.contains(display.grid.displayKey) ?? true {
            let candidates = display.windows.compactMap { window -> AutoTileLayout.Candidate? in
                let why = reason(window)
                guard isEligible(window, reason: why, config: cfg.autoTile) else { return nil }
                return AutoTileLayout.Candidate(id: window.id, frame: window.frame, reason: why)
            }
            let placements = AutoTileLayout.plan(
                candidates,
                grid: display.grid.grid,
                area: display.grid.area,
                gap: display.grid.gap,
                maximizeSingleWindow: cfg.autoTile.maximizeSingleWindow
            )
            apply(placements, to: display.windows, displayKey: display.grid.displayKey)
        }
    }

    /// Auto-tile manages standard, resizable windows (not panels, dialogs, or fixed-size
    /// HUDs) that aren't excluded or tiny. A layout pass covers every window on its display,
    /// so a yes from the AX check is cached, and the check is only made for a window that
    /// just arrived or moved — one AX couldn't resolve yet is asked again when it next moves.
    private func isEligible(_ window: WindowInfo, reason: AutoTileLayout.Reason, config: AutoTileConfig) -> Bool {
        if let bundleID = window.bundleID, config.excludedBundleIDs.contains(bundleID) {
            return false
        }
        if window.frame.width < config.minimumSize || window.frame.height < config.minimumSize {
            return false
        }
        if tileable.contains(window.id) {
            return true
        }
        guard reason != .unchanged, manager.isTileable(window) else {
            return false
        }
        tileable.insert(window.id)
        return true
    }

    private func apply(_ placements: [AutoTileLayout.Placement], to windows: [WindowInfo], displayKey: String) {
        let windowsByID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
        for placement in placements {
            guard let window = windowsByID[placement.windowID] else { continue }
            if let frame = placement.frame {
                do {
                    try manager.setFrame(window, frame: frame)
                } catch {
                    log.error("autoTile: failed to set frame for window \(window.id, privacy: .public)")
                    continue
                }
                let slot = String(describing: placement.slot)
                log.debug("autoTile: window \(window.id, privacy: .public) → \(slot, privacy: .public)")
            }
            setAssignment(windowID: window.id, displayKey: displayKey, slot: placement.slot)
        }
    }

    // MARK: - Assignment State

    // Internal (not private): also called from the split-navigation actions in
    // TilingModule+SplitActions.swift.
    func setAssignment(windowID: Int, displayKey: String, row: Int, col: Int) {
        setAssignment(windowID: windowID, displayKey: displayKey, slot: .cell(row: row, col: col))
    }

    private func setAssignment(windowID: Int, displayKey: String, slot: AutoTileLayout.Slot) {
        assignments[windowID] = GridAssignment(displayKey: displayKey, slot: slot)
    }

    func removeAssignment(windowID: Int) {
        assignments.removeValue(forKey: windowID)
    }
}

private struct GridAssignment {
    let displayKey: String
    var slot: AutoTileLayout.Slot
}
