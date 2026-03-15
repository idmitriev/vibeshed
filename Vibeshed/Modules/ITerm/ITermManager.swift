import AppKit
import Foundation
import OSLog

private let log = Log.module("iterm")

// MARK: - Data Types

struct ITermSession: Sendable {
    let sessionID: String
    let name: String
    let tty: String
    let profileName: String
    let cwd: String?
    let jobName: String?
    let isAtPrompt: Bool
    let windowID: Int
    let tabIndex: Int
}

// MARK: - Manager

enum ITermManager {
    static func isRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.googlecode.iterm2"
        }
    }

    /// Lists all sessions across all windows and tabs.
    static func listSessions() async throws -> [ITermSession] {
        log.debug("Listing iTerm sessions")
        let script = buildListSessionsScript()
        let output = try await runScript(script)
        let sessions = parseSessions(output)
        log.debug("Found \(sessions.count, privacy: .public) iTerm sessions")
        return sessions
    }

    /// Focuses a session by its GUID, bringing its window and tab
    /// to the front.
    static func focusSession(id: String) async throws {
        let script = buildFocusSessionScript(id: id)
        try await runScript(script)
    }

    /// Writes text to a session as if typed. Includes a newline
    /// by default (i.e. executes the command).
    static func writeToSession(
        id: String,
        text: String,
        newline: Bool = true
    ) async throws {
        let escaped = text.escapedForAppleScript
        let nl = newline ? "" : " newline no"
        let script = """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if id of s is "\(id)" then
                                tell s to write text "\(escaped)"\(nl)
                                return "ok"
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """
        try await runScript(script)
    }

    /// Creates a new tab in the current window, optionally with
    /// a specific profile and/or initial command.
    static func createTab(
        profile: String?,
        command: String?
    ) async throws {
        let profileClause = profilePart(profile)
        let commandClause = commandPart(command)
        let script = """
            tell application "iTerm2"
                if (count of windows) is 0 then
                    create window with \(profileClause)\(commandClause)
                else
                    tell current window
                        create tab with \(profileClause)\(commandClause)
                    end tell
                end if
                activate
            end tell
            """
        try await runScript(script)
    }

    /// Creates a new window, optionally with a specific profile
    /// and/or initial command.
    static func createWindow(
        profile: String?,
        command: String?
    ) async throws {
        let profileClause = profilePart(profile)
        let commandClause = commandPart(command)
        let script = """
            tell application "iTerm2"
                create window with \(profileClause)\(commandClause)
                activate
            end tell
            """
        try await runScript(script)
    }

    // MARK: - Script Builders

    private static func buildListSessionsScript() -> String {
        """
        tell application "iTerm2"
            set d to "\t"
            set output to ""
            repeat with w in windows
                set wid to id of w
                set tIdx to 0
                repeat with t in tabs of w
                    set tIdx to tIdx + 1
                    repeat with s in sessions of t
                        set sname to name of s
                        set stty to tty of s
                        set sprof to profile name of s
                        set sid to id of s
                        set satshell to is at shell prompt of s
                        tell s
                            set sjob to (variable named "jobName")
                            set spath to (variable named "path")
                        end tell
                        set ln to sid & d & sname & d & stty
                        set ln to ln & d & sprof & d & sjob
                        set ln to ln & d & spath & d & satshell
                        set ln to ln & d & wid & d & tIdx
                        set output to output & ln & "\n"
                    end repeat
                end repeat
            end repeat
            output
        end tell
        """
    }

    private static func buildFocusSessionScript(id: String) -> String {
        """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if id of s is "\(id)" then
                            select s
                        end if
                    end repeat
                end repeat
            end repeat
            activate
        end tell
        """
    }

    // MARK: - Parsing

    private static func parseSessions(
        _ output: String
    ) -> [ITermSession] {
        let trimmed = output.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else { return [] }

        return trimmed.components(separatedBy: "\n").compactMap { line in
            parseSessionLine(line)
        }
    }

    private static func parseSessionLine(
        _ line: String
    ) -> ITermSession? {
        let parts = line.split(
            separator: "\t",
            maxSplits: 8,
            omittingEmptySubsequences: false
        )
        guard parts.count >= 9 else { return nil }

        let sessionID = String(parts[0])
        let name = String(parts[1])
        let tty = String(parts[2])
        let profileName = String(parts[3])
        let jobName = nonEmpty(String(parts[4]))
        let cwd = nonEmpty(String(parts[5]))
        let isAtPrompt = String(parts[6]) == "true"
        let windowID = Int(parts[7]) ?? 0
        let tabIndex = Int(parts[8]) ?? 0

        return ITermSession(
            sessionID: sessionID,
            name: name,
            tty: tty,
            profileName: profileName,
            cwd: cwd,
            jobName: jobName,
            isAtPrompt: isAtPrompt,
            windowID: windowID,
            tabIndex: tabIndex
        )
    }

    // MARK: - Helpers

    private static func profilePart(_ profile: String?) -> String {
        if let profile, !profile.isEmpty {
            return "profile \"\(profile.escapedForAppleScript)\""
        }
        return "default profile"
    }

    private static func commandPart(_ command: String?) -> String {
        if let command, !command.isEmpty {
            return " command \"\(command.escapedForAppleScript)\""
        }
        return ""
    }

    private static func nonEmpty(_ str: String) -> String? {
        let trimmed = str.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if trimmed.isEmpty || trimmed == "missing value" {
            return nil
        }
        return trimmed
    }

    // MARK: - Script Runner

    @discardableResult
    private static func runScript(_ script: String) async throws -> String {
        guard isRunning() else {
            log.debug("iTerm not running, skipping script")
            throw AppleScriptError.appNotRunning("iTerm2")
        }
        return try await AppleScriptRunner.run(script)
    }
}
