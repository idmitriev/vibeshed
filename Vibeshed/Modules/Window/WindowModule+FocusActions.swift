import AppKit

/// `window/focusLeft`, `focusRight`, `focusUp`, `focusDown`: focus the nearest window on
/// that side of the focused one (see `DirectionalFocus`).
extension WindowModule {
    func buildDirectionalFocusActions(mgr: WindowManager) -> [WindowAction] {
        DirectionalFocus.Direction.allCases.map { direction in
            WindowAction(
                id: ActionID(module: "window", name: direction.actionName),
                title: direction.title,
                subtitle: "Focus the nearest window \(direction.phrase) the focused one",
                iconName: direction.iconName,
                keywords: ["focus", "window", "switch", "move", "direction", direction.rawValue]
            ) { _ in
                let (focused, windows) = await MainActor.run {
                    (mgr.getFocusedWindow(), mgr.listWindows(includeMinimized: false))
                }
                guard let focused else {
                    return .showResult(title: "No Window", body: "No focused window found")
                }
                if let target = DirectionalFocus.target(from: focused, direction: direction, among: windows) {
                    try mgr.focusWindow(target)
                }
                return .dismiss
            }
        }
    }
}

private extension DirectionalFocus.Direction {
    var actionName: String {
        switch self {
        case .left: "focusLeft"
        case .right: "focusRight"
        case .up: "focusUp"
        case .down: "focusDown"
        }
    }

    var title: String {
        switch self {
        case .left: "Focus Window on the Left"
        case .right: "Focus Window on the Right"
        case .up: "Focus Window Above"
        case .down: "Focus Window Below"
        }
    }

    var phrase: String {
        switch self {
        case .left: "to the left of"
        case .right: "to the right of"
        case .up: "above"
        case .down: "below"
        }
    }

    var iconName: String {
        "arrow.\(rawValue).square"
    }
}
