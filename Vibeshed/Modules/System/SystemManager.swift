import AppKit
import Foundation
import OSLog

private let log = Log.module("system")

enum SystemManager {

    // MARK: - Power

    static func lockScreen() {
        runProcessIgnoringErrors("/usr/bin/pmset", "displaysleepnow")
    }

    static func sleep() {
        runProcessIgnoringErrors("/usr/bin/pmset", "sleepnow")
    }

    static func restart() throws {
        let script = "tell application \"System Events\" to restart"
        try runAppleScript(script)
    }

    static func shutdown() throws {
        let script = "tell application \"System Events\" to shut down"
        try runAppleScript(script)
    }

    static func logout() throws {
        let script = "tell application \"System Events\" to log out"
        try runAppleScript(script)
    }

    // MARK: - Appearance

    static func toggleAppearance() throws {
        let script = """
        tell application "System Events"
            tell appearance preferences
                set dark mode to not dark mode
            end tell
        end tell
        """
        try runAppleScript(script)
    }

    static func setAutoAppearance() throws {
        // Remove explicit dark/light override so the system follows its schedule
        runProcessIgnoringErrors("/usr/bin/defaults", "delete", "NSGlobalDomain", "AppleInterfaceStyle")

        try runProcess("/usr/bin/defaults", "write", "NSGlobalDomain", "AppleInterfaceStyleSwitchesAutomatically", "-bool", "true")

        // Notify the system of the change
        try? AppleScriptRunner.runSync("""
            tell application "System Events"
                tell appearance preferences
                    set dark mode to dark mode
                end tell
            end tell
        """)
    }

    // MARK: - Trash

    static func emptyTrash() throws {
        let script = """
        tell application "Finder"
            empty the trash
        end tell
        """
        try runAppleScript(script)
    }

    // MARK: - Screenshots

    static func takeScreenshot(toClipboard: Bool, path: String) throws {
        if toClipboard {
            try runProcess("/usr/sbin/screencapture", "-c")
        } else {
            let expanded = NSString(string: path).expandingTildeInPath
            let timestamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            try runProcess("/usr/sbin/screencapture", "\(expanded)/Screenshot \(timestamp).png")
        }
    }

    static func takeScreenshotInteractive(path: String) throws {
        let expanded = NSString(string: path).expandingTildeInPath
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filePath = "\(expanded)/Screenshot \(timestamp).png"
        // Don't wait — interactive capture runs until user finishes selection
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-i", filePath]
        try task.run()
    }

    // MARK: - Mission Control

    static func missionControl() {
        runProcessIgnoringErrors("/usr/bin/open", "-a", "Mission Control")
    }

    // MARK: - System Maintenance

    static func flushDNS() throws {
        try runProcess("/usr/bin/dscacheutil", "-flushcache")
        try runProcess("/usr/bin/sudo", "killall", "-HUP", "mDNSResponder")
    }

    static func purgeMemory() throws {
        try runProcess("/usr/bin/sudo", "purge")
    }

    // MARK: - Private

    private static func runAppleScript(_ source: String) throws {
        try AppleScriptRunner.runSync(source)
    }

    private static func runProcess(_ path: String, _ args: String...) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        try task.run()
        task.waitUntilExit()
    }

    private static func runProcessIgnoringErrors(_ path: String, _ args: String...) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            log.warning("\(path) failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
