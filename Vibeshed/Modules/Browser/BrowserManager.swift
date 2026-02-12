import AppKit
import Foundation

enum BrowserError: Error, LocalizedError {
    case scriptFailed(String)
    case browserNotRunning(String)
    case tabNotFound(String)
    case scriptTimeout

    var errorDescription: String? {
        switch self {
        case .scriptFailed(let stderr): "AppleScript error: \(stderr)"
        case .browserNotRunning(let name): "Browser '\(name)' is not running"
        case .tabNotFound(let id): "Tab not found: \(id)"
        case .scriptTimeout: "AppleScript execution timed out"
        }
    }
}

/// Thread-safe one-shot gate for resuming a continuation exactly once.
private final class ResumeGate<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    private let continuation: CheckedContinuation<T, Error>

    init(continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<T, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        continuation.resume(with: result)
    }
}

struct BrowserManager: Sendable {
    // MARK: - Tab Listing

    func listTabs(for bundleID: String, browserName: String) async throws -> [TabInfo] {
        let script = bundleID == "com.apple.Safari"
            ? safariListScript()
            : chromiumListScript(bundleID: bundleID)
        let output = try await runAppleScript(script)
        return parseTabOutput(output, bundleID: bundleID, browserName: browserName)
    }

    func listAllTabs(browsers: [(name: String, bundleID: String)]) async -> [TabInfo] {
        await withTaskGroup(of: [TabInfo].self, returning: [TabInfo].self) { group in
            for browser in browsers {
                guard BrowserRegistry.isRunning( browser.bundleID) else { continue }
                group.addTask {
                    (try? await self.listTabs(for: browser.bundleID, browserName: browser.name)) ?? []
                }
            }
            var all: [TabInfo] = []
            for await tabs in group {
                all.append(contentsOf: tabs)
            }
            return all
        }
    }

    // MARK: - Focus Tab

    func focusTab(_ tab: TabInfo) async throws {
        guard BrowserRegistry.isRunning( tab.browserBundleID) else {
            throw BrowserError.browserNotRunning(tab.browserName)
        }

        // Re-query to get current indices
        let currentTabs = try await listTabs(for: tab.browserBundleID, browserName: tab.browserName)
        guard let current = currentTabs.first(where: { $0.title == tab.title && $0.url == tab.url })
            ?? currentTabs.first(where: { $0.url == tab.url })
        else {
            throw BrowserError.tabNotFound(tab.displayLabel)
        }

        let script = tab.browserBundleID == "com.apple.Safari"
            ? safariFocusScript(windowIndex: current.windowIndex, tabIndex: current.tabIndex)
            : chromiumFocusScript(
                bundleID: tab.browserBundleID,
                windowIndex: current.windowIndex,
                tabIndex: current.tabIndex
            )
        try await runAppleScript(script)
        await activateBrowser(bundleID: tab.browserBundleID)
    }

    // MARK: - Close Tab

    func closeTab(_ tab: TabInfo) async throws {
        guard BrowserRegistry.isRunning( tab.browserBundleID) else {
            throw BrowserError.browserNotRunning(tab.browserName)
        }

        let currentTabs = try await listTabs(for: tab.browserBundleID, browserName: tab.browserName)
        guard let current = currentTabs.first(where: { $0.title == tab.title && $0.url == tab.url })
            ?? currentTabs.first(where: { $0.url == tab.url })
        else {
            throw BrowserError.tabNotFound(tab.displayLabel)
        }

        let script = tab.browserBundleID == "com.apple.Safari"
            ? safariCloseScript(windowIndex: current.windowIndex, tabIndex: current.tabIndex)
            : chromiumCloseScript(
                bundleID: tab.browserBundleID,
                windowIndex: current.windowIndex,
                tabIndex: current.tabIndex
            )
        try await runAppleScript(script)
    }

    // MARK: - Open URL

    func openURL(_ urlString: String, in bundleID: String) async throws {
        let escaped = escapeForAppleScript(urlString)
        let script: String
        if bundleID == "com.apple.Safari" {
            script = """
                tell application "Safari"
                    activate
                    if (count of windows) = 0 then
                        make new document with properties {URL:"\(escaped)"}
                    else
                        tell window 1
                            set current tab to (make new tab with properties {URL:"\(escaped)"})
                        end tell
                    end if
                end tell
                """
        } else {
            script = """
                tell application id "\(bundleID)"
                    activate
                    if (count of windows) = 0 then
                        make new window
                        set URL of active tab of window 1 to "\(escaped)"
                    else
                        tell window 1
                            set newTab to make new tab with properties {URL:"\(escaped)"}
                        end tell
                    end if
                end tell
                """
        }
        try await runAppleScript(script)
        await activateBrowser(bundleID: bundleID)
    }

    // MARK: - Private: Script Builders

    private func safariListScript() -> String {
        """
        tell application "Safari"
            set output to ""
            set wIdx to 1
            repeat with w in windows
                set tIdx to 1
                repeat with t in tabs of w
                    set tabTitle to name of t
                    set tabURL to URL of t
                    if tabTitle is missing value then set tabTitle to ""
                    if tabURL is missing value then set tabURL to ""
                    set output to output & tabTitle & "\t" & tabURL & "\t" & wIdx & "\t" & tIdx & linefeed
                    set tIdx to tIdx + 1
                end repeat
                set wIdx to wIdx + 1
            end repeat
            return output
        end tell
        """
    }

    private func chromiumListScript(bundleID: String) -> String {
        """
        tell application id "\(bundleID)"
            set output to ""
            set wIdx to 1
            repeat with w in windows
                set tIdx to 1
                repeat with t in tabs of w
                    set tabTitle to title of t
                    set tabURL to URL of t
                    if tabTitle is missing value then set tabTitle to ""
                    if tabURL is missing value then set tabURL to ""
                    set output to output & tabTitle & "\t" & tabURL & "\t" & wIdx & "\t" & tIdx & linefeed
                    set tIdx to tIdx + 1
                end repeat
                set wIdx to wIdx + 1
            end repeat
            return output
        end tell
        """
    }

    private func safariFocusScript(windowIndex: Int, tabIndex: Int) -> String {
        """
        tell application "Safari"
            set current tab of window \(windowIndex) to tab \(tabIndex) of window \(windowIndex)
            set index of window \(windowIndex) to 1
        end tell
        """
    }

    private func chromiumFocusScript(bundleID: String, windowIndex: Int, tabIndex: Int) -> String {
        """
        tell application id "\(bundleID)"
            set active tab index of window \(windowIndex) to \(tabIndex)
            set index of window \(windowIndex) to 1
        end tell
        """
    }

    private func safariCloseScript(windowIndex: Int, tabIndex: Int) -> String {
        """
        tell application "Safari"
            close tab \(tabIndex) of window \(windowIndex)
        end tell
        """
    }

    private func chromiumCloseScript(bundleID: String, windowIndex: Int, tabIndex: Int) -> String {
        """
        tell application id "\(bundleID)"
            close tab \(tabIndex) of window \(windowIndex)
        end tell
        """
    }

    // MARK: - Private: AppleScript Execution

    @discardableResult
    private func runAppleScript(_ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")

            let inputPipe = Pipe()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardInput = inputPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let gate = ResumeGate(continuation: continuation)

            let timeoutWorkItem = DispatchWorkItem {
                gate.resume(with: .failure(BrowserError.scriptTimeout))
                process.terminate()
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeoutWorkItem)

            process.terminationHandler = { _ in
                timeoutWorkItem.cancel()

                let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                if process.terminationStatus != 0 {
                    let errorMsg = String(data: errorData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
                    gate.resume(with: .failure(BrowserError.scriptFailed(errorMsg)))
                } else {
                    let output = String(data: outputData, encoding: .utf8) ?? ""
                    gate.resume(with: .success(output))
                }
            }

            do {
                try process.run()
                inputPipe.fileHandleForWriting.write(script.data(using: .utf8) ?? Data())
                inputPipe.fileHandleForWriting.closeFile()
            } catch {
                timeoutWorkItem.cancel()
                gate.resume(with: .failure(error))
            }
        }
    }

    // MARK: - Private: Parsing

    private func parseTabOutput(_ output: String, bundleID: String, browserName: String) -> [TabInfo] {
        output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count == 4,
                  let windowIndex = Int(parts[2]),
                  let tabIndex = Int(parts[3])
            else {
                return nil
            }
            let title = String(parts[0])
            let url = String(parts[1])
            return TabInfo(
                id: "\(bundleID):\(windowIndex):\(tabIndex)",
                title: title,
                url: url,
                windowIndex: windowIndex,
                tabIndex: tabIndex,
                browserBundleID: bundleID,
                browserName: browserName
            )
        }
    }

    // MARK: - Private: Helpers

    private func escapeForAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    @MainActor
    private func activateBrowser(bundleID: String) {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first?.activate()
    }
}
