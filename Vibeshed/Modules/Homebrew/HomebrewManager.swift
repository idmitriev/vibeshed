import AppKit
import OSLog

private let log = Log.module("homebrew")

enum HomebrewManager {
    struct PackageInfo: Sendable {
        let name: String
        let version: String?
        let description: String?
        let isCask: Bool
    }

    // MARK: - Search

    static func searchFormulae(_ query: String, brewPath: String) async throws -> [PackageInfo] {
        let output = try await runBrew(brewPath, "search", "--formula", query)
        return parseSearchResults(output, isCask: false)
    }

    static func searchCasks(_ query: String, brewPath: String) async throws -> [PackageInfo] {
        let output = try await runBrew(brewPath, "search", "--cask", query)
        return parseSearchResults(output, isCask: true)
    }

    // MARK: - Install / Uninstall

    static func installFormula(_ name: String, brewPath: String) async throws -> String {
        try await runBrew(brewPath, "install", "--formula", name)
    }

    static func installCask(_ name: String, brewPath: String) async throws -> String {
        try await runBrew(brewPath, "install", "--cask", name)
    }

    /// Brew's one-line install summary (the `🍺` line, e.g. `/opt/homebrew/Cellar/jq/1.7.1: 19 files, 1.3MB`),
    /// falling back to the last output line. Full install output is too noisy for a notification.
    static func installSummary(_ output: String) -> String {
        let lines = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let summary = lines.last { $0.hasPrefix("🍺") } ?? lines.last { !$0.isEmpty } ?? ""
        return summary.drop { $0 == "🍺" || $0.isWhitespace }.description
    }

    static func uninstallFormula(_ name: String, brewPath: String) async throws -> String {
        try await runBrew(brewPath, "uninstall", "--formula", name)
    }

    static func uninstallCask(_ name: String, brewPath: String) async throws -> String {
        try await runBrew(brewPath, "uninstall", "--cask", name)
    }

    // MARK: - List Installed

    static func listInstalledFormulae(brewPath: String) async throws -> [PackageInfo] {
        let output = try await runBrew(brewPath, "list", "--formula", "--versions")
        return parseInstalledList(output, isCask: false)
    }

    static func listInstalledCasks(brewPath: String) async throws -> [PackageInfo] {
        let output = try await runBrew(brewPath, "list", "--cask", "--versions")
        return parseInstalledList(output, isCask: true)
    }

    // MARK: - Info

    static func info(_ name: String, isCask: Bool, brewPath: String) async throws -> String {
        let flag = isCask ? "--cask" : "--formula"
        return try await runBrew(brewPath, "info", flag, name)
    }

    /// Installed locations of a cask's `app` artifacts (e.g. `/Applications/Foo.app`).
    /// Empty for casks that ship no app bundle (fonts, pkg installers, CLI tools).
    static func caskAppPaths(_ name: String, brewPath: String) async throws -> [String] {
        let output = try await runBrew(brewPath, "info", "--cask", "--json=v2", name)
        return parseCaskAppPaths(Data(output.utf8))
    }

    static func parseCaskAppPaths(_ json: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let casks = root["casks"] as? [[String: Any]]
        else { return [] }
        return casks.flatMap { cask -> [String] in
            let artifacts = cask["artifacts"] as? [[String: Any]] ?? []
            return artifacts.compactMap { artifact in
                guard artifact["app"] != nil else { return nil }
                return artifact["target"] as? String
            }
        }
    }

    // MARK: - Launch

    /// Opens the first of `paths` that exists on disk. Returns the launched app's path.
    static func launchFirstApp(at paths: [String]) async -> String? {
        guard let path = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return nil
        }
        do {
            _ = try await NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: path),
                configuration: .init()
            )
            return path
        } catch {
            log.warning("Failed to launch \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Update / Upgrade

    static func update(brewPath: String) async throws -> String {
        try await runBrew(brewPath, "update")
    }

    static func upgrade(brewPath: String) async throws -> String {
        try await runBrew(brewPath, "upgrade")
    }

    static func outdated(brewPath: String) async throws -> [PackageInfo] {
        let output = try await runBrew(brewPath, "outdated", "--verbose")
        return output
            .split(separator: "\n")
            .compactMap { line -> PackageInfo? in
                let name = String(line.split(separator: " ").first ?? "")
                guard !name.isEmpty else { return nil }
                return PackageInfo(name: name, version: nil, description: String(line), isCask: false)
            }
    }

    // MARK: - Cleanup

    static func cleanup(brewPath: String) async throws -> String {
        try await runBrew(brewPath, "cleanup")
    }

    // MARK: - Private

    private static func parseSearchResults(_ output: String, isCask: Bool) -> [PackageInfo] {
        output
            .split(separator: "\n")
            .map { line in
                let name = String(line).trimmingCharacters(in: .whitespaces)
                return PackageInfo(name: name, version: nil, description: nil, isCask: isCask)
            }
            .filter { !$0.name.isEmpty && !$0.name.hasPrefix("==>") }
    }

    private static func parseInstalledList(_ output: String, isCask: Bool) -> [PackageInfo] {
        output
            .split(separator: "\n")
            .compactMap { line -> PackageInfo? in
                let parts = line.split(separator: " ", maxSplits: 1)
                guard let name = parts.first else { return nil }
                let version = parts.count > 1 ? String(parts[1]) : nil
                return PackageInfo(
                    name: String(name),
                    version: version,
                    description: nil,
                    isCask: isCask
                )
            }
    }

    @discardableResult
    private static func runBrew(_ brewPath: String, _ args: String...) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: brewPath)
            task.arguments = args
            task.environment = [
                "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                "HOME": NSHomeDirectory(),
                "HOMEBREW_NO_AUTO_UPDATE": "1",
                "HOMEBREW_NO_ANALYTICS": "1",
            ]

            let pipe = Pipe()
            let errPipe = Pipe()
            task.standardOutput = pipe
            task.standardError = errPipe

            do {
                try task.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            // Drain both pipes concurrently before waiting on exit: brew output (e.g. `search`,
            // `list --versions`) regularly exceeds the 64KB pipe buffer, and waitUntilExit()
            // before reading deadlocks — the child blocks on a full-buffer write() while we
            // block waiting for it to exit. Draining stdout/stderr sequentially isn't enough
            // either, since the other pipe can fill up while we wait on the first.
            let readGroup = DispatchGroup()
            // Safe: readGroup.wait() below is a happens-before barrier against both writes.
            nonisolated(unsafe) var data = Data()
            nonisolated(unsafe) var errData = Data()
            readGroup.enter()
            DispatchQueue.global(qos: .utility).async {
                data = pipe.fileHandleForReading.readDataToEndOfFile()
                readGroup.leave()
            }
            readGroup.enter()
            DispatchQueue.global(qos: .utility).async {
                errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                readGroup.leave()
            }
            readGroup.wait()
            task.waitUntilExit()

            let output = String(data: data, encoding: .utf8) ?? ""

            if task.terminationStatus != 0 {
                let errOutput = String(data: errData, encoding: .utf8) ?? ""
                let message = errOutput.isEmpty ? output : errOutput
                log.warning("brew \(args.joined(separator: " ")) failed: \(message, privacy: .public)")
                continuation
                    .resume(throwing: HomebrewError
                        .commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines)))
                return
            }

            continuation.resume(returning: output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

enum HomebrewError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(message): message
        }
    }
}
