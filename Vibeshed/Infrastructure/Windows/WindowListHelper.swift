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

    /// Current on-screen bounds (CG coordinates) of a single window, or nil if the
    /// window is not on screen. Note the bounds are the window's *live* window-server
    /// rect: during Mission Control / App Exposé windows stay listed but at scattered
    /// thumbnail positions that no longer match their AX-reported frame.
    static func onScreenBounds(of windowID: Int) -> CGRect? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[CFString: Any]] else {
            return nil
        }

        for entry in windowList {
            guard let id = entry[kCGWindowNumber] as? Int, id == windowID else { continue }
            guard let boundsDict = entry[kCGWindowBounds] as? [String: Double],
                  let x = boundsDict["X"],
                  let y = boundsDict["Y"],
                  let width = boundsDict["Width"],
                  let height = boundsDict["Height"]
            else {
                return nil
            }
            return CGRect(x: x, y: y, width: width, height: height)
        }
        return nil
    }

    /// Collect non-empty titles of on-screen windows owned by any app in `owners`
    /// (matched against `kCGWindowOwnerName`). Used to detect which projects/workspaces
    /// an editor currently has open.
    static func windowTitles(forOwners owners: Set<String>) -> Set<String> {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[CFString: Any]] else {
            return []
        }

        var titles = Set<String>()
        for window in windowList {
            guard let ownerName = window[kCGWindowOwnerName] as? String,
                  owners.contains(ownerName),
                  let title = window[kCGWindowName] as? String,
                  !title.isEmpty
            else { continue }
            titles.insert(title)
        }
        return titles
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

    /// Determine which NSScreen contains the center of a CG-coordinate frame.
    @MainActor
    static func screen(forFrame frame: CGRect) -> NSScreen? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        for screen in NSScreen.screens {
            let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
            let fullCG = CGRect(
                x: screen.frame.origin.x,
                y: primaryHeight - screen.frame.origin.y - screen.frame.height,
                width: screen.frame.width,
                height: screen.frame.height
            )
            if fullCG.contains(center) {
                return screen
            }
        }
        return NSScreen.main
    }

    /// Determine which screen contains the center of a CG-coordinate frame.
    @MainActor
    static func screenForFrame(_ frame: CGRect) -> CGRect {
        guard let screen = screen(forFrame: frame) else { return .zero }
        return WindowSizing.visibleFrameCG(of: screen)
    }

    /// Candidate match keys for a screen, most-specific first: its display name
    /// (`NSScreen.localizedName`, e.g. "Kuycon P20", exact match), then "main" for the
    /// primary display (NSScreen.screens.first, consistent with this codebase's existing
    /// primary-screen convention), then its 0-based positional index. Shared by any
    /// per-display config that matches against a screen (Tiling grids, Window stops).
    @MainActor
    static func candidateMatchKeys(for screen: NSScreen) -> [String] {
        guard let index = NSScreen.screens.firstIndex(of: screen) else { return [] }
        var keys: [String] = []
        if !screen.localizedName.isEmpty {
            keys.append(screen.localizedName)
        }
        if index == 0 {
            keys.append("main")
        }
        keys.append(String(index))
        return keys
    }
}
