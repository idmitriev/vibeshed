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
        case .accessibilityError(let msg):
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

    // MARK: - Focus Window

    func focusWindow(_ window: WindowInfo) throws {
        guard let axWindow = AXWindowHelper.resolve(windowID: window.id, pid: window.pid, frame: window.frame) else {
            log.error("focusWindow: could not resolve windowID=\(window.id) pid=\(window.pid)")
            throw WindowManagerError.windowNotFound
        }
        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        if let app = NSRunningApplication(processIdentifier: window.pid) {
            app.activate(options: [])
        }
    }

    // MARK: - Set Frame

    func setFrame(_ window: WindowInfo, frame: CGRect) throws {
        guard let axWindow = AXWindowHelper.resolve(windowID: window.id, pid: window.pid, frame: window.frame) else {
            log.error("setFrame: could not resolve windowID=\(window.id) pid=\(window.pid)")
            throw WindowManagerError.windowNotFound
        }

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
        guard let axWindow = AXWindowHelper.resolve(windowID: window.id, pid: window.pid, frame: window.frame) else {
            log.error("minimizeWindow: could not resolve windowID=\(window.id) pid=\(window.pid)")
            throw WindowManagerError.windowNotFound
        }
        AXUIElementSetAttributeValue(
            axWindow,
            kAXMinimizedAttribute as CFString,
            kCFBooleanTrue
        )
    }
}
