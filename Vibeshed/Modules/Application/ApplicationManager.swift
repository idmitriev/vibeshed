import AppKit
import ApplicationServices
import CoreGraphics

struct ApplicationManager: Sendable {
    // MARK: - List Installed Applications

    @MainActor
    func listInstalledApplications() -> [AppInfo] {
        let fileManager = FileManager.default
        let appDirs = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications",
        ]

        var seen = Set<String>()
        var apps: [AppInfo] = []
        let runningApps = NSWorkspace.shared.runningApplications
        let runningByBundleID = Dictionary(
            runningApps.compactMap { app -> (String, NSRunningApplication)? in
                guard let bid = app.bundleIdentifier else { return nil }
                return (bid, app)
            },
            uniquingKeysWith: { first, _ in first }
        )

        for dir in appDirs {
            guard let contents = try? fileManager.contentsOfDirectory(atPath: dir) else {
                continue
            }
            for item in contents where item.hasSuffix(".app") {
                let path = (dir as NSString).appendingPathComponent(item)
                let url = URL(fileURLWithPath: path)
                guard let bundle = Bundle(url: url),
                      let bundleID = bundle.bundleIdentifier,
                      !seen.contains(bundleID)
                else {
                    continue
                }
                seen.insert(bundleID)

                let name = fileManager.displayName(atPath: path)
                    .replacingOccurrences(of: ".app", with: "")
                let running = runningByBundleID[bundleID]
                let windowCount = running.map { countWindows(for: $0.processIdentifier) } ?? 0

                apps.append(AppInfo(
                    id: bundleID,
                    name: name,
                    bundleURL: url,
                    isRunning: running != nil,
                    pid: running?.processIdentifier,
                    windowCount: windowCount
                ))
            }
        }

        // Add running apps not found in standard directories
        for app in runningApps {
            guard let bundleID = app.bundleIdentifier,
                  !seen.contains(bundleID),
                  app.activationPolicy == .regular,
                  let url = app.bundleURL
            else {
                continue
            }
            seen.insert(bundleID)
            let windowCount = countWindows(for: app.processIdentifier)
            apps.append(AppInfo(
                id: bundleID,
                name: app.localizedName ?? bundleID,
                bundleURL: url,
                isRunning: true,
                pid: app.processIdentifier,
                windowCount: windowCount
            ))
        }

        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - List Running Applications

    @MainActor
    func listRunningApplications() -> [AppInfo] {
        let runningApps = NSWorkspace.shared.runningApplications
        var apps: [AppInfo] = []

        for app in runningApps {
            guard app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier,
                  let url = app.bundleURL
            else {
                continue
            }
            let windowCount = countWindows(for: app.processIdentifier)
            apps.append(AppInfo(
                id: bundleID,
                name: app.localizedName ?? bundleID,
                bundleURL: url,
                isRunning: true,
                pid: app.processIdentifier,
                windowCount: windowCount
            ))
        }

        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Launch Application

    @MainActor
    func launchApplication(_ app: AppInfo) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        try await NSWorkspace.shared.openApplication(at: app.bundleURL, configuration: configuration)
    }

    // MARK: - Focus Application

    @MainActor
    func focusApplication(_ app: AppInfo) -> Bool {
        guard let running = findRunningApp(bundleID: app.id) else { return false }

        if running == NSWorkspace.shared.frontmostApplication {
            // Already frontmost — cycle to next window
            cycleWindows(for: running)
        } else {
            running.activate(options: [])
        }
        return true
    }

    // MARK: - Quit Application

    @MainActor
    func quitApplication(_ app: AppInfo) -> Bool {
        guard let running = findRunningApp(bundleID: app.id) else { return false }
        return running.terminate()
    }

    // MARK: - Window Cycling

    @MainActor
    private func cycleWindows(for app: NSRunningApplication) {
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXWindowsAttribute as CFString, &windowsRef
        ) == .success,
            let axWindows = windowsRef as? [AXUIElement],
            axWindows.count > 1
        else {
            // Single or no windows — just activate
            app.activate(options: [])
            return
        }

        // Find the currently focused window
        var focusedRef: CFTypeRef?
        let hasFocused = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &focusedRef
        ) == .success

        if hasFocused, let focusedWindow = focusedRef {
            // Find index of focused window and raise next one
            var focusedID: CGWindowID = 0
            // swiftlint:disable:next force_cast
            _ = _AXUIElementGetWindow(focusedWindow as! AXUIElement, &focusedID)

            for (i, axWindow) in axWindows.enumerated() {
                var windowID: CGWindowID = 0
                _ = _AXUIElementGetWindow(axWindow, &windowID)
                if windowID == focusedID {
                    let nextIndex = (i + 1) % axWindows.count
                    AXUIElementPerformAction(axWindows[nextIndex], kAXRaiseAction as CFString)
                    app.activate(options: [])
                    return
                }
            }
        }

        // Fallback: raise first window
        AXUIElementPerformAction(axWindows[0], kAXRaiseAction as CFString)
        app.activate(options: [])
    }

    // MARK: - Private Helpers

    @MainActor
    private func findRunningApp(bundleID: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    private func countWindows(for pid: pid_t) -> Int {
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
}
