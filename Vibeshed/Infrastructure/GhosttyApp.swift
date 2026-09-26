import AppKit
import Foundation

/// The Ghostty terminal seen from outside: whether it's installed or running, what its
/// version can be automated with, and config reloads. Shared by the Ghostty module and
/// the theme module's Ghostty target.
enum GhosttyApp {
    static let bundleID = "com.mitchellh.ghostty"

    /// Ghostty's AppleScript dictionary (windows, tabs, terminals) arrived in 1.3.
    static let scriptingVersion = Version(major: 1, minor: 3)
    /// The macOS app reloads its config on SIGUSR2 since 1.2.
    static let reloadSignalVersion = Version(major: 1, minor: 2)

    struct Version: Comparable, Sendable, CustomStringConvertible {
        let major: Int
        let minor: Int

        init(major: Int, minor: Int) {
            self.major = major
            self.minor = minor
        }

        /// Parses the leading `major.minor` of a version string ("1.3.1", "1.3.2-dev").
        init?(parsing string: String) {
            let parts = string.split(separator: ".").prefix(2).map { Int($0.prefix { $0.isNumber }) }
            guard parts.count == 2, let major = parts[0], let minor = parts[1] else { return nil }
            self.init(major: major, minor: minor)
        }

        var description: String {
            "\(major).\(minor)"
        }

        static func < (lhs: Version, rhs: Version) -> Bool {
            (lhs.major, lhs.minor) < (rhs.major, rhs.minor)
        }
    }

    enum AppError: LocalizedError {
        case notInstalled
        case scriptingUnsupported(Version?)

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                "Ghostty is not installed"
            case let .scriptingUnsupported(version):
                "Ghostty \(version?.description ?? "(unknown version)") can't be scripted — update to 1.3 or later"
            }
        }
    }

    static var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static var isInstalled: Bool {
        appURL != nil
    }

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    static var installedVersion: Version? {
        appURL.flatMap(version(ofBundleAt:))
    }

    /// Throws unless the installed Ghostty understands the AppleScript the module sends.
    static func requireScripting() throws {
        guard isInstalled else { throw AppError.notInstalled }
        let version = installedVersion
        guard let version, version >= scriptingVersion else { throw AppError.scriptingUnsupported(version) }
    }

    /// Reads Info.plist directly rather than through `Bundle`, which caches it for the life
    /// of the process and would keep reporting the old version after Ghostty updates.
    static func version(ofBundleAt url: URL) -> Version? {
        let plist = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
        return (plist?["CFBundleShortVersionString"] as? String).flatMap(Version.init(parsing:))
    }

    // MARK: - Config reload

    struct ReloadResult: Equatable, Sendable {
        /// Instances sent the reload signal.
        var reloaded = 0
        /// Instances too old to reload on a signal; they need ⌘⇧, (Reload Configuration).
        var outdated = 0
    }

    /// Makes every running Ghostty re-read its config files — and the theme they name —
    /// by sending it SIGUSR2. The signal's default action is to terminate, so a Ghostty
    /// older than 1.2 (no handler) is never signalled, and neither is one still launching:
    /// it installs the handler at the end of launch, having only just read its config.
    @discardableResult
    static func reloadConfig() -> ReloadResult {
        var result = ReloadResult()
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            guard let url = app.bundleURL, let version = version(ofBundleAt: url),
                  version >= reloadSignalVersion
            else {
                result.outdated += 1
                continue
            }
            guard hasSettled(app) else { continue }
            if kill(app.processIdentifier, SIGUSR2) == 0 {
                result.reloaded += 1
            }
        }
        return result
    }

    private static func hasSettled(_ app: NSRunningApplication) -> Bool {
        guard app.isFinishedLaunching else { return false }
        guard let launched = app.launchDate else { return true }
        return Date().timeIntervalSince(launched) > 2
    }
}
