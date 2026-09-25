import AppKit
import ApplicationServices
import CoreGraphics
import OSLog

private let log = Log.module("window")

enum WindowManagerError: Error, LocalizedError {
    case noFocusedWindow
    case windowNotFound
    case accessibilityError(String)

    var errorDescription: String? {
        switch self {
        case .noFocusedWindow:
            "No focused window found"
        case .windowNotFound:
            "Window not found"
        case let .accessibilityError(msg):
            "Accessibility error: \(msg)"
        }
    }
}

struct WindowManager: Sendable {
    // MARK: - List Windows

    @MainActor
    func listWindows(includeMinimized: Bool) -> [WindowInfo] {
        WindowListHelper.listWindows(includeMinimized: includeMinimized)
    }

    // MARK: - Get Focused Window

    @MainActor
    func getFocusedWindow() -> WindowInfo? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = frontApp.processIdentifier

        guard let axWindow = AXWindowHelper.focusedWindow(for: pid) else { return nil }

        let frame = AXWindowHelper.frame(of: axWindow)
        let title = AXWindowHelper.title(of: axWindow)
        let screenFrame = WindowListHelper.screenForFrame(frame)
        let windowID = AXWindowHelper.windowID(for: axWindow).map { Int($0) } ?? 0

        return WindowInfo(
            id: windowID,
            title: title,
            appName: frontApp.localizedName ?? "",
            bundleID: frontApp.bundleIdentifier,
            pid: pid,
            frame: frame,
            screenFrame: screenFrame,
            isOnScreen: true,
            isMinimized: false
        )
    }

    /// The window's AX element; logs and throws `.windowNotFound` when it can't be resolved.
    private func axElement(for window: WindowInfo, caller: String) throws -> AXUIElement {
        guard let axWindow = AXWindowHelper.resolve(windowID: window.id, pid: window.pid, frame: window.frame) else {
            let ids = "windowID=\(window.id) pid=\(window.pid)"
            log.error("\(caller, privacy: .public): could not resolve \(ids, privacy: .public)")
            throw WindowManagerError.windowNotFound
        }
        return axWindow
    }

    // MARK: - Focus Window

    func focusWindow(_ window: WindowInfo) throws {
        let axWindow = try axElement(for: window, caller: "focusWindow")
        if AXWindowHelper.isMinimized(axWindow) {
            AXWindowHelper.deminiaturize(axWindow)
        }
        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        if let app = NSRunningApplication(processIdentifier: window.pid) {
            app.activate(options: [])
        }
    }

    // MARK: - Set Frame

    func setFrame(_ window: WindowInfo, frame: CGRect) throws {
        let axWindow = try axElement(for: window, caller: "setFrame")

        // Set position first, then size (order matters for anchoring)
        var origin = frame.origin
        guard let posValue = AXValueCreate(.cgPoint, &origin) else {
            log.error("setFrame: failed to create AXValue for position")
            throw WindowManagerError.accessibilityError("Failed to create position value")
        }
        AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, posValue)

        var size = frame.size
        guard let sizeValue = AXValueCreate(.cgSize, &size) else {
            log.error("setFrame: failed to create AXValue for size")
            throw WindowManagerError.accessibilityError("Failed to create size value")
        }
        AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)

        // Set position again after resize in case the window constrained its size
        // and the position needs adjustment (e.g., right-anchored)
        AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, posValue)
    }

    // MARK: - Minimize

    func minimizeWindow(_ window: WindowInfo) throws {
        let axWindow = try axElement(for: window, caller: "minimizeWindow")
        AXUIElementSetAttributeValue(
            axWindow,
            kAXMinimizedAttribute as CFString,
            kCFBooleanTrue
        )
    }

    @MainActor
    func minimizeAllWindows() -> Int {
        let windows = listWindows(includeMinimized: false)
        var count = 0
        for window in windows {
            if let axWindow = AXWindowHelper.resolve(windowID: window.id, pid: window.pid, frame: window.frame) {
                AXUIElementSetAttributeValue(
                    axWindow,
                    kAXMinimizedAttribute as CFString,
                    kCFBooleanTrue
                )
                count += 1
            }
        }
        return count
    }

    // MARK: - Per-Display Stops

    /// Resolves the horizontal/vertical stop lists to use for a window's frame, based on
    /// which physical display it's on. Falls back to the top-level `config.horizontalStops`/
    /// `verticalStops` if no `displays[]` entry matches, or the matched entry leaves a
    /// dimension nil.
    @MainActor
    func resolveStops(for frame: CGRect, config: WindowConfig) -> (horizontal: [SizeStop], vertical: [SizeStop]) {
        guard let screen = WindowListHelper.screen(forFrame: frame) else {
            return (config.horizontalStops, config.verticalStops)
        }
        let keys = WindowListHelper.candidateMatchKeys(for: screen)
        let matched = keys.lazy.compactMap { key in config.displays.first(where: { $0.match == key }) }.first
        let horizontal = matched?.horizontalStops ?? config.horizontalStops
        let vertical = matched?.verticalStops ?? config.verticalStops
        return (horizontal, vertical)
    }

    // MARK: - Tileability

    /// True if `window` is a normal, resizable content window — i.e. worth tiling.
    /// Filters out tooltips, HUDs, panels, dialogs, and other non-standard/fixed-size
    /// windows that shouldn't be forced into a grid cell.
    func isTileable(_ window: WindowInfo) -> Bool {
        guard let axWindow = AXWindowHelper.resolve(windowID: window.id, pid: window.pid, frame: window.frame) else {
            return false
        }
        return AXWindowHelper.isStandardWindow(axWindow) && AXWindowHelper.isResizable(axWindow)
    }
}
