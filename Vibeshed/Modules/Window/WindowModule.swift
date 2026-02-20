import AppKit
import Foundation
import OSLog

// MARK: - Helper Types

private struct TileFunctions {
    let primary: (CGRect, PaddingConfig) -> CGRect
    let opposite: (CGRect, PaddingConfig) -> CGRect
}

private struct OppositeTileInfo {
    let name: String
    let icon: String
}

private struct TileActionMetadata {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let keywords: [String]
}

actor WindowModule: ModuleConfigurable {
    let id = "window"
    let displayName = "Window Management"
    let iconName = "macwindow"
    var isEnabled = true

    typealias Config = WindowConfig
    static var defaultConfig: Config? { .defaultValue }

    static var requiredPermissions: Set<Permission> {
        [.accessibility, .screenRecording]
    }

    private var config: WindowConfig = .defaultValue
    private let windowManager = WindowManager()
    private var context: ModuleContext?
    private let log = Log.module("window")

    func initialize(context: ModuleContext) async throws {
        self.context = context
        log.info("Window module initialized")
    }

    func configDidUpdate(_ config: WindowConfig) async {
        self.config = config
        log.debug(
            "Config updated: \(config.horizontalStops.count, privacy: .public) h-stops, \(config.verticalStops.count, privacy: .public) v-stops"
        )
    }

    static func validate(_ config: WindowConfig) -> ConfigValidationResult {
        var errors: [String] = []
        if config.horizontalStops.isEmpty {
            errors.append("horizontalStops must not be empty")
        }
        if config.verticalStops.isEmpty {
            errors.append("verticalStops must not be empty")
        }
        for (i, stop) in config.horizontalStops.enumerated() {
            if stop.value <= 0 {
                errors.append("horizontalStops[\(i)].value must be positive")
            }
        }
        for (i, stop) in config.verticalStops.enumerated() {
            if stop.value <= 0 {
                errors.append("verticalStops[\(i)].value must be positive")
            }
        }
        if config.padding.top < 0 || config.padding.bottom < 0
            || config.padding.left < 0 || config.padding.right < 0 {
            errors.append("Padding values must be non-negative")
        }
        if config.padding.gap < 0 {
            errors.append("Gap must be non-negative")
        }
        if config.enlargeShrinkStep.value <= 0 {
            errors.append("enlargeShrinkStep.value must be positive")
        }
        if config.toggleMaximizeRestoreSize.value <= 0 {
            errors.append("toggleMaximizeRestoreSize.value must be positive")
        }
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    func provideActions(query: String, scoring: ScoringContext) async -> [any Action] {
        let allActions = buildActions()
        guard !query.isEmpty else { return allActions }
        let lowered = query.lowercased()
        return allActions.filter { action in
            action.title.lowercased().contains(lowered)
                || action.subtitle.lowercased().contains(lowered)
                || action.keywords.contains { $0.contains(lowered) }
        }
    }

    func provideParameterOptions(
        for parameterID: String,
        in _: ActionID,
        query: String
    ) async -> [ParameterOption] {
        guard parameterID == "window" else { return [] }
        let includeMinimized = config.includeMinimized
        let windows = await MainActor.run {
            windowManager.listWindows(includeMinimized: includeMinimized)
        }
        let options = windows.map { window in
            ParameterOption(
                id: String(window.id),
                label: window.displayLabel,
                iconName: "macwindow"
            )
        }
        guard !query.isEmpty else { return options }
        let lowered = query.lowercased()
        return options.filter { $0.label.lowercased().contains(lowered) }
    }

    // MARK: - Build Actions

    private func buildActions() -> [WindowAction] {
        let mgr = windowManager
        let cfg = config

        var actions: [WindowAction] = []
        actions.append(contentsOf: buildCycleActions(mgr: mgr, cfg: cfg))
        actions.append(contentsOf: buildPositionActions(mgr: mgr, cfg: cfg))
        actions.append(contentsOf: buildTileActions(mgr: mgr, cfg: cfg))
        actions.append(contentsOf: buildResizeActions(mgr: mgr, cfg: cfg))
        return actions
    }

    private func buildCycleActions(mgr: WindowManager, cfg: WindowConfig) -> [WindowAction] {
        [
            makeCycleAction(
                id: "cycleLeft", title: "Cycle Width (Left)",
                subtitle: "Cycle through width stops anchored to left edge",
                icon: "rectangle.lefthalf.inset.filled.arrow.left",
                anchor: Anchor.left, horizontal: true, mgr: mgr, cfg: cfg
            ),
            makeCycleAction(
                id: "cycleRight", title: "Cycle Width (Right)",
                subtitle: "Cycle through width stops anchored to right edge",
                icon: "rectangle.righthalf.inset.filled.arrow.right",
                anchor: Anchor.right, horizontal: true, mgr: mgr, cfg: cfg
            ),
            makeCycleAction(
                id: "cycleTop", title: "Cycle Height (Top)",
                subtitle: "Cycle through height stops anchored to top edge",
                icon: "rectangle.tophalf.inset.filled",
                anchor: Anchor.top, horizontal: false, mgr: mgr, cfg: cfg
            ),
            makeCycleAction(
                id: "cycleBottom", title: "Cycle Height (Bottom)",
                subtitle: "Cycle through height stops anchored to bottom edge",
                icon: "rectangle.bottomhalf.inset.filled",
                anchor: Anchor.bottom, horizontal: false, mgr: mgr, cfg: cfg
            ),
        ]
    }

    private func makeCycleAction(
        id: String, title: String, subtitle: String, icon: String,
        anchor: Anchor, horizontal: Bool,
        mgr: WindowManager, cfg: WindowConfig
    ) -> WindowAction {
        let keywords = ["cycle", horizontal ? "horizontal" : "vertical", "resize", "size"]
        return WindowAction(
            id: ActionID(module: "window", name: id),
            title: title, subtitle: subtitle, iconName: icon, keywords: keywords
        ) { _ in
            guard let focused = await MainActor.run(body: { mgr.getFocusedWindow() }) else {
                return .showResult(title: "No Window", body: "No focused window found")
            }
            let newFrame: CGRect
            if horizontal {
                newFrame = WindowSizing.cycleHorizontal(
                    currentFrame: focused.frame,
                    screenFrame: focused.screenFrame,
                    padding: cfg.padding,
                    stops: cfg.horizontalStops,
                    anchor: anchor
                )
            } else {
                newFrame = WindowSizing.cycleVertical(
                    currentFrame: focused.frame,
                    screenFrame: focused.screenFrame,
                    padding: cfg.padding,
                    stops: cfg.verticalStops,
                    anchor: anchor
                )
            }
            try mgr.setFrame(focused, frame: newFrame)
            return .dismiss
        }
    }

    private func buildPositionActions(mgr: WindowManager, cfg: WindowConfig) -> [WindowAction] {
        [
            WindowAction(
                id: ActionID(module: "window", name: "maximize"),
                title: "Maximize Window",
                subtitle: "Expand window to fill the screen",
                iconName: "arrow.up.left.and.arrow.down.right",
                relevanceScore: 0.9,
                keywords: ["maximize", "full", "expand", "fill"]
            ) { _ in
                guard let focused = await MainActor.run(body: { mgr.getFocusedWindow() }) else {
                    return .showResult(title: "No Window", body: "No focused window found")
                }
                let newFrame = WindowSizing.maximize(
                    screenFrame: focused.screenFrame,
                    padding: cfg.padding
                )
                try mgr.setFrame(focused, frame: newFrame)
                return .dismiss
            },
            WindowAction(
                id: ActionID(module: "window", name: "center"),
                title: "Center Window",
                subtitle: "Center window on screen keeping its size",
                iconName: "dot.square",
                keywords: ["center", "middle"]
            ) { _ in
                guard let focused = await MainActor.run(body: { mgr.getFocusedWindow() }) else {
                    return .showResult(title: "No Window", body: "No focused window found")
                }
                let newFrame = WindowSizing.center(
                    currentSize: focused.frame.size,
                    screenFrame: focused.screenFrame,
                    padding: cfg.padding
                )
                try mgr.setFrame(focused, frame: newFrame)
                return .dismiss
            },
            WindowAction(
                id: ActionID(module: "window", name: "minimize"),
                title: "Minimize Window",
                subtitle: "Minimize the focused window to the Dock",
                iconName: "minus",
                keywords: ["minimize", "hide", "dock"]
            ) { _ in
                guard let focused = await MainActor.run(body: { mgr.getFocusedWindow() }) else {
                    return .showResult(title: "No Window", body: "No focused window found")
                }
                try mgr.minimizeWindow(focused)
                return .dismiss
            },
            makeFocusWindowAction(mgr: mgr),
            makeToggleMaximizeAction(mgr: mgr, cfg: cfg),
        ]
    }

    private func makeFocusWindowAction(mgr: WindowManager) -> WindowAction {
        WindowAction(
            id: ActionID(module: "window", name: "focusWindow"),
            title: "Focus Window",
            subtitle: "Focus a specific window",
            iconName: "macwindow",
            relevanceScore: 0.7,
            keywords: ["focus", "window", "switch", "activate"],
            parameters: [
                ActionParameter(
                    id: "window",
                    label: "Window",
                    type: .dynamicSelection(hint: "window"),
                    isRequired: true
                ),
            ]
        ) { values in
            guard let windowIDString = values["window"] as? String,
                  let windowID = Int(windowIDString)
            else {
                return .showResult(title: "Error", body: "No window selected")
            }
            let windows = await MainActor.run {
                mgr.listWindows(includeMinimized: true)
            }
            guard let target = windows.first(where: { $0.id == windowID }) else {
                return .showResult(title: "Error", body: "Window not found")
            }
            try mgr.focusWindow(target)
            return .dismiss
        }
    }

    private func makeToggleMaximizeAction(mgr: WindowManager, cfg: WindowConfig) -> WindowAction {
        WindowAction(
            id: ActionID(module: "window", name: "toggleMaximize"),
            title: "Toggle Maximize/Restore",
            subtitle: "Toggle between maximized and restored window size",
            iconName: "arrow.up.left.and.arrow.down.right.circle",
            relevanceScore: 0.95,
            keywords: ["toggle", "maximize", "restore", "expand", "contract", "fullscreen"]
        ) { _ in
            guard let focused = await MainActor.run(body: { mgr.getFocusedWindow() }) else {
                return .showResult(title: "No Window", body: "No focused window found")
            }
            let newFrame = WindowSizing.toggleMaximize(
                currentFrame: focused.frame,
                currentSize: focused.frame.size,
                screenFrame: focused.screenFrame,
                padding: cfg.padding,
                restoreSize: cfg.toggleMaximizeRestoreSize
            )
            try mgr.setFrame(focused, frame: newFrame)
            return .dismiss
        }
    }

    private func buildTileActions(mgr: WindowManager, cfg: WindowConfig) -> [WindowAction] {
        [
            makeTileAction(
                meta: TileActionMetadata(
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
                meta: TileActionMetadata(
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
                meta: TileActionMetadata(
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
                meta: TileActionMetadata(
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
        meta: TileActionMetadata,
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

    private func buildResizeActions(mgr: WindowManager, cfg: WindowConfig) -> [WindowAction] {
        [
            makeResizeAction(
                id: "enlargeWidth", title: "Enlarge Width",
                subtitle: "Increase window width while keeping anchor position",
                icon: "arrow.right.and.line.vertical.and.arrow.left",
                keywords: ["enlarge", "width", "expand", "horizontal", "grow", "bigger"],
                resizeFunc: WindowSizing.enlargeHorizontal, mgr: mgr, cfg: cfg
            ),
            makeResizeAction(
                id: "shrinkWidth", title: "Shrink Width",
                subtitle: "Decrease window width while keeping anchor position",
                icon: "arrow.left.and.line.vertical.and.arrow.right",
                keywords: ["shrink", "width", "reduce", "horizontal", "smaller", "narrow"],
                resizeFunc: WindowSizing.shrinkHorizontal, mgr: mgr, cfg: cfg
            ),
            makeResizeAction(
                id: "enlargeHeight", title: "Enlarge Height",
                subtitle: "Increase window height while keeping anchor position",
                icon: "arrow.down.and.line.horizontal.and.arrow.up",
                keywords: ["enlarge", "height", "expand", "vertical", "grow", "bigger", "taller"],
                resizeFunc: WindowSizing.enlargeVertical, mgr: mgr, cfg: cfg
            ),
            makeResizeAction(
                id: "shrinkHeight", title: "Shrink Height",
                subtitle: "Decrease window height while keeping anchor position",
                icon: "arrow.up.and.line.horizontal.and.arrow.down",
                keywords: ["shrink", "height", "reduce", "vertical", "smaller", "shorter"],
                resizeFunc: WindowSizing.shrinkVertical, mgr: mgr, cfg: cfg
            ),
        ]
    }

    private func makeResizeAction(
        id: String, title: String, subtitle: String, icon: String, keywords: [String],
        resizeFunc: @escaping (CGRect, CGRect, PaddingConfig, SizeStop) -> CGRect,
        mgr: WindowManager, cfg: WindowConfig
    ) -> WindowAction {
        WindowAction(
            id: ActionID(module: "window", name: id),
            title: title, subtitle: subtitle, iconName: icon, keywords: keywords
        ) { _ in
            guard let focused = await MainActor.run(body: { mgr.getFocusedWindow() }) else {
                return .showResult(title: "No Window", body: "No focused window found")
            }
            let newFrame = resizeFunc(
                focused.frame, focused.screenFrame, cfg.padding, cfg.enlargeShrinkStep
            )
            try mgr.setFrame(focused, frame: newFrame)
            return .dismiss
        }
    }
}
