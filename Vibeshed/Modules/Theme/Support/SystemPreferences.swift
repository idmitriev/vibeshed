import Foundation

/// Reads and writes other domains' user preferences (the `defaults` command's scope:
/// current user, any host) and posts the distributed notifications apps listen to for
/// live updates. Never replaces a whole domain — `UserDefaults.setPersistentDomain` on
/// the global domain would wipe every other global setting.
enum SystemPreferences {
    /// `NSGlobalDomain` / `defaults -g`.
    static let globalDomain = kCFPreferencesAnyApplication as String

    static func value(_ key: String, domain: String = globalDomain) -> Any? {
        CFPreferencesCopyValue(
            key as CFString, domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost
        )
    }

    /// Sets (or with `nil`, removes) a key. Returns false if the domain couldn't be
    /// written — e.g. `com.apple.universalaccess` without Full Disk Access.
    @discardableResult
    static func set(_ value: Any?, forKey key: String, domain: String = globalDomain) -> Bool {
        // Foundation values bridge to their CF property-list counterparts via AnyObject.
        let propertyList: CFPropertyList? = value.map { $0 as AnyObject }
        CFPreferencesSetValue(
            key as CFString, propertyList, domain as CFString,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost
        )
        return CFPreferencesSynchronize(domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    static func postDistributed(_ names: [String]) {
        let center = DistributedNotificationCenter.default()
        for name in names {
            center.postNotificationName(
                NSNotification.Name(name), object: nil, userInfo: nil, deliverImmediately: true
            )
        }
    }
}

/// Runs a shell command line through the user's login shell (so Homebrew and other
/// `PATH` additions resolve, as they would in Terminal).
enum ShellCommand {
    struct Result: Sendable {
        let status: Int32
        let output: String
    }

    static func run(
        _ command: String,
        environment: [String: String] = [:],
        timeout: TimeInterval = 20
    ) async -> Result {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-lc", command]
                process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                process.standardInput = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: Result(status: -1, output: error.localizedDescription))
                    return
                }
                let timer = DispatchWorkItem { process.terminate() }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
                // Drain before waiting: waitUntilExit() first deadlocks past the 64KB pipe buffer.
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                timer.cancel()
                let output = String(bytes: data, encoding: .utf8) ?? ""
                continuation.resume(returning: Result(
                    status: process.terminationStatus,
                    output: output.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
            }
        }
    }
}
