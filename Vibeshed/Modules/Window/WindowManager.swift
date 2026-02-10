import AppKit
import ApplicationServices
import CoreGraphics

// Private SPI to get CGWindowID from an AXUIElement
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ outWindowID: UnsafeMutablePointer<CGWindowID>) -> AXError

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
        var options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        if includeMinimized {
            options = [.excludeDesktopElements]
        }

        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
            as? [[CFString: Any]]
        else {
            return []
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier

        var results: [WindowInfo] = []
        for entry in windowList {
            guard let windowID = entry[kCGWindowNumber] as? Int,
                  let ownerPID = entry[kCGWindowOwnerPID] as? pid_t,
                  let layer = entry[kCGWindowLayer] as? Int,
                  layer == 0,
                  ownerPID != ownPID
            else {
                continue
            }

            let appName = entry[kCGWindowOwnerName] as? String ?? ""
            let title = entry[kCGWindowName] as? String ?? ""
            let isOnScreen = entry[kCGWindowIsOnscreen] as? Bool ?? false

            guard let boundsDict = entry[kCGWindowBounds] as? [String: Double],
                  let x = boundsDict["X"],
                  let y = boundsDict["Y"],
                  let w = boundsDict["Width"],
                  let h = boundsDict["Height"]
            else {
                continue
            }

            let frame = CGRect(x: x, y: y, width: w, height: h)
            let screenFrame = screenForFrame(frame)

            let bundleID = NSRunningApplication(processIdentifier: ownerPID)?
                .bundleIdentifier

            let isMinimized = !isOnScreen && includeMinimized

            results.append(WindowInfo(
                id: windowID,
                title: title,
                appName: appName,
                bundleID: bundleID,
                pid: ownerPID,
                frame: frame,
                screenFrame: screenFrame,
                isOnScreen: isOnScreen,
                isMinimized: isMinimized
            ))
        }

        return results
    }

    // MARK: - Get Focused Window

    @MainActor
    func getFocusedWindow() -> WindowInfo? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = frontApp.processIdentifier

        let appElement = AXUIElementCreateApplication(pid)
        var focusedRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedRef
        )
        guard result == .success, let windowElement = focusedRef else { return nil }

        // swiftlint:disable:next force_cast
        let axWindow = windowElement as! AXUIElement
        let frame = axWindowFrame(axWindow)
        let title = axWindowTitle(axWindow)
        let screenFrame = screenForFrame(frame)

        // Get the CGWindowID for this AX window
        var windowID: CGWindowID = 0
        _ = _AXUIElementGetWindow(axWindow, &windowID)

        return WindowInfo(
            id: Int(windowID),
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
        guard let axWindow = resolveAXWindow(for: window) else {
            throw WindowManagerError.windowNotFound
        }
        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        if let app = NSRunningApplication(processIdentifier: window.pid) {
            app.activate(options: [])
        }
    }

    // MARK: - Set Frame

    func setFrame(_ window: WindowInfo, frame: CGRect) throws {
        guard let axWindow = resolveAXWindow(for: window) else {
            throw WindowManagerError.windowNotFound
        }

        // Set position first, then size (order matters for anchoring)
        var origin = frame.origin
        guard let posValue = AXValueCreate(.cgPoint, &origin) else {
            throw WindowManagerError.accessibilityError("Failed to create position value")
        }
        AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, posValue)

        var size = frame.size
        guard let sizeValue = AXValueCreate(.cgSize, &size) else {
            throw WindowManagerError.accessibilityError("Failed to create size value")
        }
        AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)

        // Set position again after resize in case the window constrained its size
        // and the position needs adjustment (e.g., right-anchored)
        AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, posValue)
    }

    // MARK: - Minimize

    func minimizeWindow(_ window: WindowInfo) throws {
        guard let axWindow = resolveAXWindow(for: window) else {
            throw WindowManagerError.windowNotFound
        }
        AXUIElementSetAttributeValue(
            axWindow,
            kAXMinimizedAttribute as CFString,
            kCFBooleanTrue
        )
    }

    // MARK: - Private: Resolve AXUIElement

    private func resolveAXWindow(for window: WindowInfo) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(window.pid)

        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsRef
        )
        guard result == .success,
              let axWindows = windowsRef as? [AXUIElement]
        else {
            return nil
        }

        // First try matching by CGWindowID
        for axWindow in axWindows {
            var axWindowID: CGWindowID = 0
            _ = _AXUIElementGetWindow(axWindow, &axWindowID)
            if Int(axWindowID) == window.id {
                return axWindow
            }
        }

        // Fallback: match by frame proximity
        let tolerance: Double = 5.0
        for axWindow in axWindows {
            let axFrame = axWindowFrame(axWindow)
            if abs(axFrame.origin.x - window.frame.origin.x) <= tolerance,
               abs(axFrame.origin.y - window.frame.origin.y) <= tolerance,
               abs(axFrame.width - window.frame.width) <= tolerance,
               abs(axFrame.height - window.frame.height) <= tolerance
            {
                return axWindow
            }
        }

        return nil
    }

    // MARK: - Private: AX Helpers

    private func axWindowFrame(_ element: AXUIElement) -> CGRect {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        var point = CGPoint.zero
        var size = CGSize.zero

        if AXUIElementCopyAttributeValue(
            element, kAXPositionAttribute as CFString, &positionRef
        ) == .success,
            let posValue = positionRef
        {
            // swiftlint:disable:next force_cast
            AXValueGetValue(posValue as! AXValue, .cgPoint, &point)
        }

        if AXUIElementCopyAttributeValue(
            element, kAXSizeAttribute as CFString, &sizeRef
        ) == .success,
            let szValue = sizeRef
        {
            // swiftlint:disable:next force_cast
            AXValueGetValue(szValue as! AXValue, .cgSize, &size)
        }

        return CGRect(origin: point, size: size)
    }

    private func axWindowTitle(_ element: AXUIElement) -> String {
        var titleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element, kAXTitleAttribute as CFString, &titleRef
        ) == .success {
            return titleRef as? String ?? ""
        }
        return ""
    }

    // MARK: - Private: Screen Detection

    @MainActor
    private func screenForFrame(_ frame: CGRect) -> CGRect {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        for screen in NSScreen.screens {
            let cgFrame = WindowSizing.visibleFrameCG(of: screen)
            // Use the full screen frame (not just visible) for containment check
            let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
            let fullCG = CGRect(
                x: screen.frame.origin.x,
                y: primaryHeight - screen.frame.origin.y - screen.frame.height,
                width: screen.frame.width,
                height: screen.frame.height
            )
            if fullCG.contains(center) {
                return cgFrame
            }
        }
        // Fallback to primary screen
        if let primary = NSScreen.main {
            return WindowSizing.visibleFrameCG(of: primary)
        }
        return .zero
    }
}
