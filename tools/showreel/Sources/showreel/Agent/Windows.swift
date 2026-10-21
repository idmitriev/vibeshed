import AppKit
import ApplicationServices
import ShowreelCore

/// An on-screen window, from the window server's list (front to back).
struct WindowInfo {
    var id: CGWindowID
    var pid: pid_t
    var owner: String
    var title: String
    var layer: Int
    var frame: Rect

    static func onScreen() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0
            else { return nil }
            return WindowInfo(
                id: id,
                pid: pid,
                owner: entry[kCGWindowOwnerName as String] as? String ?? "",
                title: entry[kCGWindowName as String] as? String ?? "",
                layer: entry[kCGWindowLayer as String] as? Int ?? 0,
                frame: Rect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
            )
        }
    }
}

@MainActor
enum Windows {
    static let vibeshedBundleID = "com.ivandmitriev.Vibeshed"

    /// The window a target names, if it is on screen now.
    static func find(_ target: WindowTarget) -> WindowInfo? {
        switch target {
        case .picker:
            picker()
        case let .app(name):
            Apps.running(name).flatMap { app in
                WindowInfo.onScreen().first { $0.pid == app.processIdentifier && $0.layer == 0 }
            }
        }
    }

    /// The picker panel: Vibeshed's large window at the floating level (3), or
    /// just above the overlay backdrop (status bar + 2 = 27). The keystroke
    /// visualizer sits at the screen saver level and the overlay is 26.
    static func picker() -> WindowInfo? {
        let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: vibeshedBundleID)
            .map(\.processIdentifier))
        return WindowInfo.onScreen()
            .filter { pids.contains($0.pid) && [3, 27].contains($0.layer) && $0.frame.width >= 300 }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    /// Brings `app` to the front with its front window raised, so typing reaches it.
    /// Since macOS 14 NSWorkspace's activation is a request the active app can turn
    /// down, and the agent runs in the background; Accessibility's frontmost flag isn't.
    static func bringToFront(_ app: NSRunningApplication, timeout: Double = 5) async throws {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        let deadline = Date().addingTimeInterval(timeout)
        while NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
            guard Date() < deadline else { throw AgentError("\(app.localizedName ?? "app") didn't come to the front") }
            AXUIElementSetAttributeValue(element, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            try await Task.sleep(for: .milliseconds(150))
        }
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
           let window = (value as? [AXUIElement])?.first
        {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
    }

    /// Moves and resizes an app's front window through Accessibility.
    static func place(_ app: NSRunningApplication, frame: Rect) throws {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement], let window = windows.first
        else {
            throw AgentError("\(app.localizedName ?? "app") has no window to place")
        }
        var origin = CGPoint(x: frame.x, y: frame.y)
        var size = CGSize(width: frame.width, height: frame.height)
        // Size, then position, then size again: a window that doesn't fit at
        // its old position gets clamped by the first resize.
        for (attribute, axValue) in [
            (kAXSizeAttribute, AXValueCreate(.cgSize, &size)),
            (kAXPositionAttribute, AXValueCreate(.cgPoint, &origin)),
            (kAXSizeAttribute, AXValueCreate(.cgSize, &size)),
        ] {
            guard let axValue else { continue }
            AXUIElementSetAttributeValue(window, attribute as CFString, axValue)
        }
    }

    /// Presses each window's close button, through Accessibility (AppleScript
    /// would need an Automation grant). Returns how many it closed.
    @discardableResult
    static func closeAll(of app: NSRunningApplication) -> Int {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else { return 0 }
        var closed = 0
        for window in windows {
            var button: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &button) == .success,
                  let button, CFGetTypeID(button) == AXUIElementGetTypeID()
            else { continue }
            // Checked above: the attribute holds an AXUIElement.
            let closeButton = unsafeDowncast(button, to: AXUIElement.self)
            if AXUIElementPerformAction(closeButton, kAXPressAction as CFString) == .success {
                closed += 1
            }
        }
        return closed
    }

    static func waitForWindow(of app: NSRunningApplication, timeout: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if WindowInfo.onScreen().contains(where: { $0.pid == app.processIdentifier && $0.layer == 0 }) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }
}

/// Finds apps by name ("Safari") or bundle identifier ("com.apple.Safari").
@MainActor
enum Apps {
    /// Also by the bundle's file name: Visual Studio Code.app runs as "Code".
    static func running(_ name: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == name || $0.localizedName == name
                || $0.bundleURL?.deletingPathExtension().lastPathComponent == name
        }
    }

    static func url(_ name: String) -> URL? {
        if name.hasPrefix("/") { return URL(fileURLWithPath: name) }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) { return url }
        let folders = [
            "/Applications", "/System/Applications", "/System/Applications/Utilities",
            "/System/Library/CoreServices", NSHomeDirectory() + "/Applications",
        ]
        return folders.map { URL(fileURLWithPath: "\($0)/\(name).app") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Launches (or re-opens) an app, optionally with a URL or file, and
    /// returns it once it is running.
    static func open(
        _ name: String,
        document: String? = nil,
        arguments: [String] = [],
        activate: Bool
    ) async throws -> NSRunningApplication {
        guard let appURL = url(name) else { throw AgentError("can't find app '\(name)'") }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activate
        configuration.arguments = arguments
        if let document {
            let target = document.contains("://") ? URL(string: document) : URL(fileURLWithPath: document)
            guard let target else { throw AgentError("bad URL '\(document)'") }
            return try await NSWorkspace.shared.open([target], withApplicationAt: appURL, configuration: configuration)
        }
        return try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }

    static func quit(_ app: NSRunningApplication, timeout: Double = 5) async {
        app.terminate()
        let deadline = Date().addingTimeInterval(timeout)
        while !app.isTerminated, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if !app.isTerminated {
            Log.warn("\(app.localizedName ?? "app") didn't quit in \(Int(timeout))s; force-quitting")
            app.forceTerminate()
        }
    }
}

struct AgentError: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}
