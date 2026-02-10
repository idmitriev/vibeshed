import AppKit
import Foundation

enum BrowserLauncher {
    /// Well-known browser name → bundle ID mapping.
    static let knownBrowsers: [String: String] = [
        "safari": "com.apple.Safari",
        "chrome": "com.google.Chrome",
        "firefox": "org.mozilla.firefox",
        "brave": "com.brave.Browser",
        "edge": "com.microsoft.edgemac",
        "arc": "company.thebrowser.Browser",
        "orion": "com.kagi.kagimacOS",
        "vivaldi": "com.vivaldi.Vivaldi",
        "opera": "com.operasoftware.Opera",
    ]

    /// Chromium-based browsers that support --profile-directory.
    private static let chromiumBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
    ]

    /// Resolve a browser string (name or bundle ID) to a bundle ID.
    static func resolveBundleID(_ browser: String) -> String {
        knownBrowsers[browser.lowercased()] ?? browser
    }

    /// Check if a browser is installed.
    static func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// Open a URL in a specific browser, optionally with a profile.
    static func open(url: URL, browser: String, profile: String?) throws {
        let bundleID = resolveBundleID(browser)

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw URIError.browserNotFound(browser)
        }

        let config = NSWorkspace.OpenConfiguration()
        if let profile, chromiumBundleIDs.contains(bundleID) {
            config.arguments = ["--profile-directory=\(profile)"]
        }

        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
    }

    /// Get the current system default browser bundle ID.
    static func systemDefaultBrowserBundleID() -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) else {
            return nil
        }
        return Bundle(url: url)?.bundleIdentifier
    }
}
