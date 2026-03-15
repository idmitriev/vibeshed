import AppKit
import Foundation
import OSLog

private let log = Log.module("browser")

enum BrowserError: Error, LocalizedError {
    case tabNotFound(String)

    var errorDescription: String? {
        switch self {
        case .tabNotFound(let id): "Tab not found: \(id)"
        }
    }
}

struct BrowserManager: Sendable {
    // MARK: - Tab Listing

    func listTabs(for bundleID: String, browserName: String) async throws -> [TabInfo] {
        log.debug("Listing tabs for \(browserName, privacy: .public) (\(bundleID, privacy: .public))")
        let script = bundleID == "com.apple.Safari"
            ? safariListScript()
            : chromiumListScript(bundleID: bundleID)
        let output = try await AppleScriptRunner.run(script)
        let tabs = parseTabOutput(output, bundleID: bundleID, browserName: browserName)
        log.debug("Found \(tabs.count, privacy: .public) tabs in \(browserName, privacy: .public)")
        return tabs
    }

    func listAllTabs(browsers: [(name: String, bundleID: String)]) async -> [TabInfo] {
        await withTaskGroup(of: [TabInfo].self, returning: [TabInfo].self) { group in
            for browser in browsers {
                guard BrowserRegistry.isRunning( browser.bundleID) else { continue }
                group.addTask {
                    do {
                        return try await self.listTabs(for: browser.bundleID, browserName: browser.name)
                    } catch {
                        log.warning("listAllTabs: failed for \(browser.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        return []
                    }
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
            log.error("focusTab: browser not running \(tab.browserName, privacy: .public)")
            throw AppleScriptError.appNotRunning(tab.browserName)
        }

        // Re-query to get current indices
        let currentTabs = try await listTabs(for: tab.browserBundleID, browserName: tab.browserName)
        guard let current = currentTabs.first(where: { $0.title == tab.title && $0.url == tab.url })
            ?? currentTabs.first(where: { $0.url == tab.url })
        else {
            log.error("focusTab: tab not found after re-query: \(tab.displayLabel, privacy: .public)")
            throw BrowserError.tabNotFound(tab.displayLabel)
        }

        let script = tab.browserBundleID == "com.apple.Safari"
            ? safariFocusScript(windowIndex: current.windowIndex, tabIndex: current.tabIndex)
            : chromiumFocusScript(
                bundleID: tab.browserBundleID,
                windowIndex: current.windowIndex,
                tabIndex: current.tabIndex
            )
        try await AppleScriptRunner.run(script)
        await activateBrowser(bundleID: tab.browserBundleID)
    }

    // MARK: - Close Tab

    func closeTab(_ tab: TabInfo) async throws {
        guard BrowserRegistry.isRunning( tab.browserBundleID) else {
            log.error("closeTab: browser not running \(tab.browserName, privacy: .public)")
            throw AppleScriptError.appNotRunning(tab.browserName)
        }

        let currentTabs = try await listTabs(for: tab.browserBundleID, browserName: tab.browserName)
        guard let current = currentTabs.first(where: { $0.title == tab.title && $0.url == tab.url })
            ?? currentTabs.first(where: { $0.url == tab.url })
        else {
            log.error("closeTab: tab not found after re-query: \(tab.displayLabel, privacy: .public)")
            throw BrowserError.tabNotFound(tab.displayLabel)
        }

        let script = tab.browserBundleID == "com.apple.Safari"
            ? safariCloseScript(windowIndex: current.windowIndex, tabIndex: current.tabIndex)
            : chromiumCloseScript(
                bundleID: tab.browserBundleID,
                windowIndex: current.windowIndex,
                tabIndex: current.tabIndex
            )
        try await AppleScriptRunner.run(script)
    }

    // MARK: - Open URL

    func openURL(_ urlString: String, in bundleID: String) async throws {
        let escaped = urlString.escapedForAppleScript
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
        try await AppleScriptRunner.run(script)
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

    @MainActor
    private func activateBrowser(bundleID: String) {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first?.activate()
    }
}
