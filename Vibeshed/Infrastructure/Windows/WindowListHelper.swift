import AppKit
import CoreGraphics

enum WindowListHelper {
    /// List all visible (layer 0) windows, excluding own app.
    @MainActor
    static func listWindows(includeMinimized: Bool) -> [WindowInfo] {
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

    /// Count visible windows for a specific PID.
    static func countWindows(for pid: pid_t) -> Int {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard pid != ownPID else { return 0 }

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[CFString: Any]] else {
            return 0
        }

        return windowList.filter { entry in
            guard let ownerPID = entry[kCGWindowOwnerPID] as? pid_t,
                  let layer = entry[kCGWindowLayer] as? Int,
                  layer == 0,
                  ownerPID == pid
            else {
                return false
            }
            return true
        }.count
    }

    /// Count visible windows grouped by PID in a single CGWindowList call.
    static func countWindowsByPID() -> [pid_t: Int] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[CFString: Any]] else {
            return [:]
        }
        var counts: [pid_t: Int] = [:]
        for entry in windowList {
            guard let ownerPID = entry[kCGWindowOwnerPID] as? pid_t,
                  let layer = entry[kCGWindowLayer] as? Int,
                  layer == 0,
                  ownerPID != ownPID
            else { continue }
            counts[ownerPID, default: 0] += 1
        }
        return counts
    }

    /// Determine which screen contains the center of a CG-coordinate frame.
    @MainActor
    static func screenForFrame(_ frame: CGRect) -> CGRect {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        for screen in NSScreen.screens {
            let cgFrame = WindowSizing.visibleFrameCG(of: screen)
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
        if let primary = NSScreen.main {
            return WindowSizing.visibleFrameCG(of: primary)
        }
        return .zero
    }
}
