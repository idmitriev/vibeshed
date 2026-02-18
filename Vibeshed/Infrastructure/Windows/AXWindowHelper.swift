import ApplicationServices
import CoreGraphics

// Private SPI to get CGWindowID from an AXUIElement
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ outWindowID: UnsafeMutablePointer<CGWindowID>) -> AXError

enum AXWindowHelper {
    /// Get the CGWindowID for an AXUIElement window.
    static func windowID(for element: AXUIElement) -> CGWindowID? {
        var windowID: CGWindowID = 0
        let result = _AXUIElementGetWindow(element, &windowID)
        guard result == .success else { return nil }
        return windowID
    }

    /// Get the frame (position + size) of an AX window element.
    static func frame(of element: AXUIElement) -> CGRect {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        var point = CGPoint.zero
        var size = CGSize.zero

        if AXUIElementCopyAttributeValue(
            element, kAXPositionAttribute as CFString, &positionRef
        ) == .success,
            let posValue = positionRef {
            // swiftlint:disable:next force_cast
            AXValueGetValue(posValue as! AXValue, .cgPoint, &point)
        }

        if AXUIElementCopyAttributeValue(
            element, kAXSizeAttribute as CFString, &sizeRef
        ) == .success,
            let szValue = sizeRef {
            // swiftlint:disable:next force_cast
            AXValueGetValue(szValue as! AXValue, .cgSize, &size)
        }

        return CGRect(origin: point, size: size)
    }

    /// Get the title of an AX window element.
    static func title(of element: AXUIElement) -> String {
        var titleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element, kAXTitleAttribute as CFString, &titleRef
        ) == .success {
            return titleRef as? String ?? ""
        }
        return ""
    }

    /// List all AX windows for a given PID.
    static func windows(for pid: pid_t) -> [AXUIElement] {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement, kAXWindowsAttribute as CFString, &windowsRef
        )
        guard result == .success, let axWindows = windowsRef as? [AXUIElement] else {
            return []
        }
        return axWindows
    }

    /// Get the focused AX window for a given PID.
    static func focusedWindow(for pid: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        var focusedRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &focusedRef
        )
        guard result == .success, let window = focusedRef else { return nil }
        return (window as! AXUIElement) // swiftlint:disable:this force_cast
    }

    /// Resolve a window to its AXUIElement by matching CGWindowID first, then frame proximity.
    static func resolve(windowID: Int, pid: pid_t, frame: CGRect) -> AXUIElement? {
        let axWindows = windows(for: pid)

        // First try matching by CGWindowID
        for axWindow in axWindows {
            if let axID = self.windowID(for: axWindow), Int(axID) == windowID {
                return axWindow
            }
        }

        // Fallback: match by frame proximity
        let tolerance: Double = 5.0
        for axWindow in axWindows {
            let axFrame = self.frame(of: axWindow)
            if abs(axFrame.origin.x - frame.origin.x) <= tolerance,
               abs(axFrame.origin.y - frame.origin.y) <= tolerance,
               abs(axFrame.width - frame.width) <= tolerance,
               abs(axFrame.height - frame.height) <= tolerance {
                return axWindow
            }
        }

        return nil
    }
}
