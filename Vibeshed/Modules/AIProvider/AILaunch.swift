import AppKit
import Foundation
import OSLog

private let log = Log.module("ai")

/// Shared launching primitives for the AI vendor modules: running a CLI in a fresh
/// terminal tab, opening app deeplinks, and quoting. Vendor providers differ only in
/// which binary and which URL they hand to these.
enum AILaunch {
    // MARK: - CLI resolution

    /// Resolves a vendor CLI: an explicit `customPath` if executable, else the first
    /// executable candidate, else the bare name so `PATH` lookup in the terminal can
    /// still find it.
    static func resolveCLI(
        customPath: String?,
        candidates: [String],
        fallbackName: String
    ) -> String {
        CLILauncher.resolveCLI(
            customPath: customPath, candidates: candidates, log: log
        ) ?? fallbackName
    }

    // MARK: - Terminal

    /// Runs `command` in a new tab of the user's terminal, optionally `cd`-ing first.
    /// Fire-and-forget: dispatched off the calling actor so a slow AppleScript never
    /// blocks the picker.
    static func inTerminal(
        command: String,
        cwd: String?,
        terminalApp: String?
    ) {
        let terminal = terminalApp ?? detectTerminal()
        let script = terminalScript(
            terminal: terminal,
            command: command.escapedForAppleScript,
            cwd: cwd
        )
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try AppleScriptRunner.runSync(script)
            } catch {
                log.error(
                    "Terminal launch failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private static func terminalScript(
        terminal: String,
        command: String,
        cwd: String?
    ) -> String {
        terminal == "iterm"
            ? itermScript(command: command, cwd: cwd)
            : terminalAppScript(command: command, cwd: cwd)
    }

    private static func itermScript(command: String, cwd: String?) -> String {
        let cdPart: String
        if let cwd {
            cdPart = """
                        tell current session of current window
                            write text "cd \(cwd.escapedForAppleScript)"
                        end tell

            """
        } else {
            cdPart = ""
        }
        return """
        tell application "iTerm2"
            if (count of windows) is 0 then
                create window with default profile
            else
                tell current window
                    create tab with default profile
                end tell
            end if
        \(cdPart)    tell current session of current window
                write text "\(command)"
            end tell
            activate
        end tell
        """
    }

    private static func terminalAppScript(command: String, cwd: String?) -> String {
        let cdClause = cwd.map { "cd \($0.escapedForAppleScript) && " } ?? ""
        return """
        tell application "Terminal"
            do script "\(cdClause)\(command)"
            activate
        end tell
        """
    }

    private static func detectTerminal() -> String {
        FileManager.default.fileExists(atPath: "/Applications/iTerm.app")
            ? "iterm" : "terminal"
    }

    // MARK: - Apps and URLs

    static func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            log.warning("Malformed URL: \(urlString, privacy: .public)")
            return
        }
        DispatchQueue.main.async {
            NSWorkspace.shared.open(url)
        }
    }

    /// Builds a URL from `base` plus query items, skipping items with nil values.
    static func url(_ base: String, query: [String: String?]) -> String? {
        guard var components = URLComponents(string: base) else { return nil }
        let items = query
            .compactMap { key, value in
                value.map { URLQueryItem(name: key, value: $0) }
            }
            .sorted { $0.name < $1.name }
        if !items.isEmpty {
            components.queryItems = items
        }
        return components.url?.absoluteString
    }

    static func openApp(bundleID: String) {
        DispatchQueue.main.async {
            guard let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleID
            ) else {
                log.warning("App not installed: \(bundleID, privacy: .public)")
                return
            }
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    static func isAppInstalled(bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    // MARK: - Strings

    /// POSIX shell single-quote escape: wraps in `'…'`, replacing `'` with `'\''`.
    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Trims whitespace, returning nil for empty input.
    static func trimmed(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    /// Trims and expands a leading `~` in a user-entered path.
    static func expandedPath(_ value: String?) -> String? {
        trimmed(value).map { ($0 as NSString).expandingTildeInPath }
    }
}
