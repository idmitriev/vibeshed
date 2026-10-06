import AppKit
import Foundation

/// Drives Terminal.app through its AppleScript dictionary, which can run a command in
/// a new window (`do script`) but has no way to open a tab.
enum TerminalManager {
    static let bundleID = TerminalTarget.bundleID

    static var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    /// Opens a window, running `command` in its shell when given. The shell stays open
    /// after the command exits.
    static func newWindow(command: String?) async throws {
        let launched = try await launchIfNeeded()
        // Terminal opens a window when it launches; scripting another would leave two.
        if launched, command == nil { return }
        // Generous timeout: a freshly launched Terminal takes a moment to answer.
        try await AppleScriptRunner.run(newWindowScript(command: command, afterLaunch: launched), timeout: 15)
    }

    /// Launches Terminal when it isn't running; returns whether it did.
    private static func launchIfNeeded() async throws -> Bool {
        guard !isRunning else { return false }
        try await launch()
        return true
    }

    @MainActor
    private static func launch() async throws {
        guard let url = appURL else { throw AppleScriptError.appNotRunning("Terminal") }
        try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - Scripts

    /// `do script` with no target opens a window. Right after a launch, the command runs
    /// in the window Terminal opened instead, once it's there: waits up to 3s, then opens
    /// one itself.
    static func newWindowScript(command: String?, afterLaunch: Bool) -> String {
        let doScript = "do script \"\((command ?? "").escapedForAppleScript)\""
        let lines = afterLaunch
            ? [
                "repeat 30 times",
                "if (count of windows) > 0 then exit repeat",
                "delay 0.1",
                "end repeat",
                "if (count of windows) > 0 then",
                "\(doScript) in window 1",
                "else",
                doScript,
                "end if",
            ]
            : [doScript]
        return "tell application id \"\(bundleID)\"\n" + (lines + ["activate"]).joined(separator: "\n") + "\nend tell"
    }
}
