import AppKit
import Foundation
import OSLog

private let log = Log.module("system")

enum SystemManager {

    // MARK: - Power

    static func lockScreen() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["displaysleepnow"]
        do {
            try task.run()
        } catch {
            log.warning("lockScreen: pmset failed: \(error.localizedDescription)")
        }
    }

    static func sleep() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["sleepnow"]
        do {
            try task.run()
        } catch {
            log.warning("sleep: pmset failed: \(error.localizedDescription)")
        }
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
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["delete", "NSGlobalDomain", "AppleInterfaceStyle"]
        do {
            try task.run()
        } catch {
            log.warning("setAutoAppearance: defaults delete failed: \(error.localizedDescription)")
        }
        task.waitUntilExit()

        let killTask = Process()
        killTask.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        killTask.arguments = ["write", "NSGlobalDomain", "AppleInterfaceStyleSwitchesAutomatically", "-bool", "true"]
        try killTask.run()
        killTask.waitUntilExit()

        // Notify the system of the change
        let notify = Process()
        notify.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        notify.arguments = ["-e", """
            tell application "System Events"
                tell appearance preferences
                    set dark mode to dark mode
                end tell
            end tell
        """]
        do {
            try notify.run()
        } catch {
            log.warning("setAutoAppearance: notify script failed: \(error.localizedDescription)")
        }
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
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        if toClipboard {
            task.arguments = ["-c"]
        } else {
            let expanded = NSString(string: path).expandingTildeInPath
            let timestamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let filePath = "\(expanded)/Screenshot \(timestamp).png"
            task.arguments = [filePath]
        }
        try task.run()
        task.waitUntilExit()
    }

    static func takeScreenshotInteractive(path: String) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        let expanded = NSString(string: path).expandingTildeInPath
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filePath = "\(expanded)/Screenshot \(timestamp).png"
        task.arguments = ["-i", filePath]
        try task.run()
    }

    // MARK: - System Maintenance

    static func flushDNS() throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/dscacheutil")
        task.arguments = ["-flushcache"]
        try task.run()
        task.waitUntilExit()

        let killTask = Process()
        killTask.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        killTask.arguments = ["killall", "-HUP", "mDNSResponder"]
        try killTask.run()
        killTask.waitUntilExit()
    }

    static func purgeMemory() throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["purge"]
        try task.run()
        task.waitUntilExit()
    }

    // MARK: - Private

    private static func runAppleScript(_ source: String) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", source]
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            log.error("AppleScript exited with status \(task.terminationStatus)")
        }
    }
}
