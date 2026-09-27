import AppKit
import Foundation

/// An open Ghostty terminal: a tab, or one pane of a split tab.
struct GhosttyTerminal: Sendable, Equatable {
    /// Ghostty's UUID for the surface, stable for as long as it's open.
    let id: String
    let title: String
    let workingDirectory: String?
    /// 1-based, front to back.
    let windowIndex: Int
    /// 1-based within its window.
    let tabIndex: Int

    var location: String {
        "Window \(windowIndex), tab \(tabIndex)"
    }
}

/// Drives Ghostty through its AppleScript dictionary (Ghostty 1.3+).
enum GhosttyManager {
    /// Every terminal in every window, front window first. Empty when Ghostty isn't
    /// running — asking it would launch it.
    static func listTerminals() async throws -> [GhosttyTerminal] {
        try GhosttyApp.requireScripting()
        guard GhosttyApp.isRunning else { return [] }
        let output = try await AppleScriptRunner.run(listTerminalsScript)
        return parseTerminals(output)
    }

    /// Brings the terminal's window and tab to the front and focuses it.
    static func focus(terminalID: String) async throws {
        try GhosttyApp.requireScripting()
        // A row from a stale listing must not relaunch a Ghostty that has since quit.
        guard GhosttyApp.isRunning else { throw AppleScriptError.appNotRunning("Ghostty") }
        try await AppleScriptRunner.run(focusScript(terminalID: terminalID))
    }

    /// Opens a window. `input` is typed into its shell, followed by Return.
    static func newWindow(input: String?) async throws {
        try await openSurface(inTab: false, input: input)
    }

    /// Opens a tab in Ghostty's current window, or a window when it has none.
    /// `input` is typed into its shell, followed by Return.
    static func newTab(input: String?) async throws {
        try await openSurface(inTab: true, input: input)
    }

    private static func openSurface(inTab: Bool, input: String?) async throws {
        // Launching opens Ghostty's first window; scripting a new one on top of
        // that would leave two.
        if input == nil, !GhosttyApp.isRunning {
            return try await launch()
        }
        try GhosttyApp.requireScripting()
        // Generous timeout: the script launches Ghostty first when it isn't running.
        try await AppleScriptRunner.run(newSurfaceScript(inTab: inTab, input: input), timeout: 15)
    }

    @MainActor
    private static func launch() async throws {
        guard let url = GhosttyApp.appURL else { throw GhosttyApp.AppError.notInstalled }
        try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - Scripts

    /// One line per terminal: id, title, working directory, window, tab — tab-separated
    /// (`character id 9`: inside the `tell`, `tab` means Ghostty's class).
    static let listTerminalsScript = """
    set sep to character id 9
    set out to ""
    tell application id "\(GhosttyApp.bundleID)"
        set wIdx to 0
        repeat with w in windows
            set wIdx to wIdx + 1
            set tIdx to 0
            repeat with t in tabs of w
                set tIdx to tIdx + 1
                repeat with term in terminals of t
                    set out to out & (id of term) & sep & (name of term) & sep & (working directory of term)
                    set out to out & sep & wIdx & sep & tIdx & linefeed
                end repeat
            end repeat
        end repeat
    end tell
    return out
    """

    static func focusScript(terminalID: String) -> String {
        """
        tell application id "\(GhosttyApp.bundleID)"
            focus terminal id "\(terminalID.escapedForAppleScript)"
            activate
        end tell
        """
    }

    static func newSurfaceScript(inTab: Bool, input: String?) -> String {
        var lines: [String] = []
        var configuration = ""
        if let input {
            lines.append("set cfg to new surface configuration")
            lines.append("set initial input of cfg to \"\(input.escapedForAppleScript)\" & linefeed")
            configuration = " with configuration cfg"
        }
        if inTab {
            lines += [
                "if (count of windows) is 0 then",
                "new window\(configuration)",
                "else",
                "new tab\(configuration)",
                "end if",
            ]
        } else {
            lines.append("new window\(configuration)")
        }
        lines.append("activate")
        return "tell application id \"\(GhosttyApp.bundleID)\"\n" + lines.joined(separator: "\n") + "\nend tell"
    }

    // MARK: - Parsing

    static func parseTerminals(_ output: String) -> [GhosttyTerminal] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 5, !fields[0].isEmpty,
                  let window = Int(fields[3]), let tab = Int(fields[4])
            else { return nil }
            let directory = fields[2].trimmingCharacters(in: .whitespaces)
            return GhosttyTerminal(
                id: fields[0],
                title: fields[1],
                workingDirectory: directory.isEmpty ? nil : directory,
                windowIndex: window,
                tabIndex: tab
            )
        }
    }
}
