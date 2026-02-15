import AppKit
import Foundation
import OSLog

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
        log.debug("Config updated: \(config.horizontalStops.count) h-stops, \(config.verticalStops.count) v-stops")
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
            || config.padding.left < 0 || config.padding.right < 0
        {
            errors.append("Padding values must be non-negative")
        }
        if config.padding.gap < 0 {
            errors.append("Gap must be non-negative")
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

    // swiftlint:disable:next function_body_length
    private func buildActions() -> [WindowAction] {
        let mgr = windowManager
        let cfg = config

        var actions: [WindowAction] = []

        // MARK: Cycle Width (Left anchor)
        actions.append(WindowAction(
            id: ActionID(module: "window", name: "cycleLeft"),
            title: "Cycle Width (Left)",
            subtitle: "Cycle through width stops anchored to left edge",
            iconName: "rectangle.lefthalf.inset.filled.arrow.left",
            keywords: ["cycle", "horizontal", "left", "width", "resize", "size"]
        ) { _ in
            guard let focused = await MainActor.run(body: { mgr.getFocusedWindow() }) else {
                return .showResult(title: "No Window", body: "No focused window found")
            }
            let newFrame = WindowSizing.cycleHorizontal(
                currentFrame: focused.frame,
                screenFrame: focused.screenFrame,
                padding: cfg.padding,
                stops: cfg.horizontalStops,
                anchor: .left
            )
            try mgr.setFrame(focused, frame: newFrame)
            return .dismiss
        })

        // MARK: Cycle Width (Right anchor)
        actions.append(WindowAction(
            id: ActionID(module: "window", name: "cycleRight"),
            title: "Cycle Width (Right)",
            subtitle: "Cycle through width stops anchored to right edge",
            iconName: "rectangle.righthalf.inset.filled.arrow.right",
            keywords: ["cycle", "horizontal", "right", "width", "resize", "size"]
        ) { _ in
            guard let focused = await MainActor.run(body: { mgr.getFocusedWindow() }) else {
                return .showResult(title: "No Window", body: "No focused window found")
            }
            let newFrame = WindowSizing.cycleHorizontal(
                currentFrame: focused.frame,
                screenFrame: focused.screenFrame,
                padding: cfg.padding,
                stops: cfg.horizontalStops,
                anchor: .right
            )
            try mgr.setFrame(focused, frame: newFrame)
            return .dismiss
        })

        // MARK: Cycle Height (Top anchor)
        actions.append(WindowAction(
            id: ActionID(module: "window", name: "cycleTop"),
            title: "Cycle Height (Top)",
            subtitle: "Cycle through height stops anchored to top edge",
            iconName: "rectangle.tophalf.inset.filled",
            keywords: ["cycle", "vertical", "top", "height", "resize", "size"]
        ) { _ in
            guard let focused = await MainActor.run(body: { mgr.getFocusedWindow() }) else {
                return .showResult(title: "No Window", body: "No focused window found")
            }
            let newFrame = WindowSizing.cycleVertical(
                currentFrame: focused.frame,
                screenFrame: focused.screenFrame,
                padding: cfg.padding,
                stops: cfg.verticalStops,
                anchor: .top
            )
            try mgr.setFrame(focused, frame: newFrame)
            return .dismiss
        })

        // MARK: Cycle Height (Bottom anchor)
        actions.append(WindowAction(
            id: ActionID(module: "window", name: "cycleBottom"),
            title: "Cycle Height (Bottom)",
            subtitle: "Cycle through height stops anchored to bottom edge",
            iconName: "rectangle.bottomhalf.inset.filled",
            keywords: ["cycle", "vertical", "bottom", "height", "resize", "size"]
        ) { _ in
            guard let focused = await MainActor.run(body: { mgr.getFocusedWindow() }) else {
                return .showResult(title: "No Window", body: "No focused window found")
            }
            let newFrame = WindowSizing.cycleVertical(
                currentFrame: focused.frame,
                screenFrame: focused.screenFrame,
                padding: cfg.padding,
                stops: cfg.verticalStops,
                anchor: .bottom
            )
            try mgr.setFrame(focused, frame: newFrame)
            return .dismiss
        })

        // MARK: Maximize
        actions.append(WindowAction(
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
        })

        // MARK: Center
        actions.append(WindowAction(
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
        })

        // MARK: Minimize
        actions.append(WindowAction(
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
        })

        // MARK: Tile Left Half
        actions.append(WindowAction(
            id: ActionID(module: "window", name: "tileLeft"),
            title: "Tile Left Half",
            subtitle: "Move focused window to left half of screen",
            iconName: "rectangle.lefthalf.filled",
            keywords: ["tile", "left", "half", "split"]
        ) { _ in
            guard let focused = await MainActor.run(body: { mgr.getFocusedWindow() }) else {
                return .showResult(title: "No Window", body: "No focused window found")
            }
            let newFrame = WindowSizing.tileLeft(
                screenFrame: focused.screenFrame,
                padding: cfg.padding
            )
            try mgr.setFrame(focused, frame: newFrame)

            // Two-window flow: offer remaining windows for right half
            let windows = await MainActor.run {
                mgr.listWindows(includeMinimized: false)
            }
            let others = windows.filter { $0.id != focused.id }
            guard !others.isEmpty else { return .dismiss }

            let tileActions = others.map { window in
                WindowAction(
                    id: ActionID(module: "window", name: "tileRightFor.\(window.id)"),
                    title: "Tile Right: \(window.displayLabel)",
                    subtitle: "Move to right half of screen",
                    iconName: "rectangle.righthalf.filled",
                    relevanceScore: 0.9,
                    keywords: ["tile", "right"]
                ) { _ in
                    let rightFrame = WindowSizing.tileRight(
                        screenFrame: focused.screenFrame,
                        padding: cfg.padding
                    )
                    try mgr.setFrame(window, frame: rightFrame)
                    try mgr.focusWindow(window)
                    return .dismiss
                }
            }
            return .pushActions(tileActions)
        })

        // MARK: Tile Right Half
        actions.append(WindowAction(
            id: ActionID(module: "window", name: "tileRight"),
            title: "Tile Right Half",
            subtitle: "Move focused window to right half of screen",
            iconName: "rectangle.righthalf.filled",
            keywords: ["tile", "right", "half", "split"]
        ) { _ in
            guard let focused = await MainActor.run(body: { mgr.getFocusedWindow() }) else {
                return .showResult(title: "No Window", body: "No focused window found")
            }
            let newFrame = WindowSizing.tileRight(
                screenFrame: focused.screenFrame,
                padding: cfg.padding
            )
            try mgr.setFrame(focused, frame: newFrame)

            let windows = await MainActor.run {
                mgr.listWindows(includeMinimized: false)
            }
            let others = windows.filter { $0.id != focused.id }
            guard !others.isEmpty else { return .dismiss }

            let tileActions = others.map { window in
                WindowAction(
                    id: ActionID(module: "window", name: "tileLeftFor.\(window.id)"),
                    title: "Tile Left: \(window.displayLabel)",
                    subtitle: "Move to left half of screen",
                    iconName: "rectangle.lefthalf.filled",
                    relevanceScore: 0.9,
                    keywords: ["tile", "left"]
                ) { _ in
                    let leftFrame = WindowSizing.tileLeft(
                        screenFrame: focused.screenFrame,
                        padding: cfg.padding
                    )
                    try mgr.setFrame(window, frame: leftFrame)
                    try mgr.focusWindow(window)
                    return .dismiss
                }
            }
            return .pushActions(tileActions)
        })

        // MARK: Tile Top Half
        actions.append(WindowAction(
            id: ActionID(module: "window", name: "tileTop"),
            title: "Tile Top Half",
            subtitle: "Move focused window to top half of screen",
            iconName: "rectangle.tophalf.filled",
            keywords: ["tile", "top", "half", "split"]
        ) { _ in
            guard let focused = await MainActor.run(body: { mgr.getFocusedWindow() }) else {
                return .showResult(title: "No Window", body: "No focused window found")
            }
            let newFrame = WindowSizing.tileTop(
                screenFrame: focused.screenFrame,
                padding: cfg.padding
            )
            try mgr.setFrame(focused, frame: newFrame)

            let windows = await MainActor.run {
                mgr.listWindows(includeMinimized: false)
            }
            let others = windows.filter { $0.id != focused.id }
            guard !others.isEmpty else { return .dismiss }

            let tileActions = others.map { window in
                WindowAction(
                    id: ActionID(module: "window", name: "tileBottomFor.\(window.id)"),
                    title: "Tile Bottom: \(window.displayLabel)",
                    subtitle: "Move to bottom half of screen",
                    iconName: "rectangle.bottomhalf.filled",
                    relevanceScore: 0.9,
                    keywords: ["tile", "bottom"]
                ) { _ in
                    let bottomFrame = WindowSizing.tileBottom(
                        screenFrame: focused.screenFrame,
                        padding: cfg.padding
                    )
                    try mgr.setFrame(window, frame: bottomFrame)
                    try mgr.focusWindow(window)
                    return .dismiss
                }
            }
            return .pushActions(tileActions)
        })

        // MARK: Tile Bottom Half
        actions.append(WindowAction(
            id: ActionID(module: "window", name: "tileBottom"),
            title: "Tile Bottom Half",
            subtitle: "Move focused window to bottom half of screen",
            iconName: "rectangle.bottomhalf.filled",
            keywords: ["tile", "bottom", "half", "split"]
        ) { _ in
            guard let focused = await MainActor.run(body: { mgr.getFocusedWindow() }) else {
                return .showResult(title: "No Window", body: "No focused window found")
            }
            let newFrame = WindowSizing.tileBottom(
                screenFrame: focused.screenFrame,
                padding: cfg.padding
            )
            try mgr.setFrame(focused, frame: newFrame)

            let windows = await MainActor.run {
                mgr.listWindows(includeMinimized: false)
            }
            let others = windows.filter { $0.id != focused.id }
            guard !others.isEmpty else { return .dismiss }

            let tileActions = others.map { window in
                WindowAction(
                    id: ActionID(module: "window", name: "tileTopFor.\(window.id)"),
                    title: "Tile Top: \(window.displayLabel)",
                    subtitle: "Move to top half of screen",
                    iconName: "rectangle.tophalf.filled",
                    relevanceScore: 0.9,
                    keywords: ["tile", "top"]
                ) { _ in
                    let topFrame = WindowSizing.tileTop(
                        screenFrame: focused.screenFrame,
                        padding: cfg.padding
                    )
                    try mgr.setFrame(window, frame: topFrame)
                    try mgr.focusWindow(window)
                    return .dismiss
                }
            }
            return .pushActions(tileActions)
        })

        // MARK: Focus Window (Picker action)
        actions.append(WindowAction(
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
        })

        return actions
    }
}
