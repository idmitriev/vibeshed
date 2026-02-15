import AppKit
import CoreGraphics
import Foundation

struct SystemContext: Sendable {
    let focusedAppBundleID: String?
    let focusedAppName: String?
    let runningAppBundleIDs: Set<String>
    let hour: Int
    let isWeekend: Bool
    let outputVolume: Float
    let isOutputMuted: Bool
    let isSpotifyRunning: Bool
    let focusedWindowTitle: String?
    let visibleWindowCount: Int

    @MainActor
    static func capture() -> SystemContext {
        let frontApp = NSWorkspace.shared.frontmostApplication
        let focusedBundleID = frontApp?.bundleIdentifier
        let focusedName = frontApp?.localizedName

        let runningBundleIDs = Set(
            NSWorkspace.shared.runningApplications
                .compactMap(\.bundleIdentifier)
        )

        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let weekday = calendar.component(.weekday, from: now)
        let isWeekend = weekday == 1 || weekday == 7

        let volume = AudioManager.getOutputVolume()
        let muted = AudioManager.isOutputMuted()

        let spotifyRunning = !NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.spotify.client")
            .isEmpty

        // Focused window title — needs accessibility, gracefully returns nil if denied
        var windowTitle: String?
        if let pid = frontApp?.processIdentifier,
           let axWindow = AXWindowHelper.focusedWindow(for: pid)
        {
            let title = AXWindowHelper.title(of: axWindow)
            if !title.isEmpty {
                windowTitle = title
            }
        }

        // Visible window count — CGWindowList works without screen recording for basic info
        let windowCount = captureVisibleWindowCount()

        return SystemContext(
            focusedAppBundleID: focusedBundleID,
            focusedAppName: focusedName,
            runningAppBundleIDs: runningBundleIDs,
            hour: hour,
            isWeekend: isWeekend,
            outputVolume: volume,
            isOutputMuted: muted,
            isSpotifyRunning: spotifyRunning,
            focusedWindowTitle: windowTitle,
            visibleWindowCount: windowCount
        )
    }

    private static func captureVisibleWindowCount() -> Int {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else {
            return 0
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        return windowList.filter { entry in
            guard let pid = entry[kCGWindowOwnerPID] as? pid_t,
                  let layer = entry[kCGWindowLayer] as? Int,
                  layer == 0,
                  pid != ownPID
            else {
                return false
            }
            return true
        }.count
    }
}
