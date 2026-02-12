import AppKit
import Foundation

struct BrowserEntry: Sendable {
    let name: String
    let bundleID: String
    let isChromium: Bool
    let supportsAppleScriptTabs: Bool
}

enum BrowserRegistry {
    static let all: [BrowserEntry] = [
        BrowserEntry(name: "Safari", bundleID: "com.apple.Safari", isChromium: false, supportsAppleScriptTabs: true),
        BrowserEntry(name: "Chrome", bundleID: "com.google.Chrome", isChromium: true, supportsAppleScriptTabs: true),
        BrowserEntry(name: "Firefox", bundleID: "org.mozilla.firefox", isChromium: false, supportsAppleScriptTabs: false),
        BrowserEntry(name: "Brave", bundleID: "com.brave.Browser", isChromium: true, supportsAppleScriptTabs: true),
        BrowserEntry(name: "Edge", bundleID: "com.microsoft.edgemac", isChromium: true, supportsAppleScriptTabs: true),
        BrowserEntry(name: "Arc", bundleID: "company.thebrowser.Browser", isChromium: false, supportsAppleScriptTabs: true),
        BrowserEntry(name: "Orion", bundleID: "com.kagi.kagimacOS", isChromium: false, supportsAppleScriptTabs: false),
        BrowserEntry(name: "Vivaldi", bundleID: "com.vivaldi.Vivaldi", isChromium: true, supportsAppleScriptTabs: true),
        BrowserEntry(name: "Opera", bundleID: "com.operasoftware.Opera", isChromium: true, supportsAppleScriptTabs: true),
    ]

    /// Browsers that support AppleScript tab access (Safari + Chromium-based, excluding Firefox/Orion).
    static var appleScriptCapable: [BrowserEntry] {
        all.filter(\.supportsAppleScriptTabs)
    }

    /// Installed browsers that support AppleScript tab access.
    static var installedAppleScriptCapable: [BrowserEntry] {
        appleScriptCapable.filter { isInstalled($0.bundleID) }
    }

    /// Resolve a browser string (name or bundle ID) to a bundle ID.
    static func resolveBundleID(_ browser: String) -> String {
        all.first(where: { $0.name.lowercased() == browser.lowercased() })?.bundleID ?? browser
    }

    /// Look up a browser name by bundle ID.
    static func name(for bundleID: String) -> String? {
        all.first(where: { $0.bundleID == bundleID })?.name
    }

    /// Look up a browser entry by bundle ID.
    static func entry(for bundleID: String) -> BrowserEntry? {
        all.first(where: { $0.bundleID == bundleID })
    }

    /// Check if a browser is installed on this system.
    static func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// Check if a browser is currently running.
    static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Get the current system default browser bundle ID.
    static func systemDefaultBundleID() -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(
            toOpen: URL(string: "https://example.com")!
        ) else {
            return nil
        }
        return Bundle(url: url)?.bundleIdentifier
    }

    /// Open a URL in a specific browser, optionally with a profile.
    static func open(url: URL, browser: String, profile: String?) throws {
        let bundleID = resolveBundleID(browser)

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw URIError.browserNotFound(browser)
        }

        let config = NSWorkspace.OpenConfiguration()
        if let profile, entry(for: bundleID)?.isChromium == true {
            config.arguments = ["--profile-directory=\(profile)"]
        }

        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
    }
}
