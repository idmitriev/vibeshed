import Foundation
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

            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if task.terminationStatus != 0 {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
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
