import AppKit
import Foundation
import OSLog

private let log = Log.module("processes")

enum ProcessesManager {
    // MARK: - List

    static func listProcesses(excludedNames: Set<String>) async throws -> [ProcessEntry] {
        let psText = try await runCommand("/bin/ps", ["-axo", "pid=,pcpu=,pmem=,comm="])
        let lsofText = (try? await runCommand("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN"])) ?? ""

        let portsByPID = parsePorts(lsofText)
        let bundleURLsByPID = await runningAppBundleURLs()

        return psText.split(separator: "\n").compactMap { line in
            parsePSLine(String(line), portsByPID: portsByPID, bundleURLsByPID: bundleURLsByPID)
        }.filter { !excludedNames.contains($0.name) }
    }

    // MARK: - Kill

    static func kill(pid: Int32, force: Bool = true) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/kill")
        task.arguments = (force ? ["-9"] : []) + [String(pid)]

        let errPipe = Pipe()
        task.standardError = errPipe
        try task.run()
        task.waitUntilExit()

        guard task.terminationStatus != 0 else { return }

        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: errData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = (message?.isEmpty == false ? message : nil) ?? "exit code \(task.terminationStatus)"
        log.warning("kill \(pid) failed: \(reason, privacy: .public)")
        throw ProcessesError.killFailed(pid: pid, message: reason ?? "unknown error")
    }

    // MARK: - Parsing

    private static func parsePSLine(
        _ line: String,
        portsByPID: [Int32: [Int]],
        bundleURLsByPID: [Int32: URL]
    ) -> ProcessEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard parts.count == 4,
              let pid = Int32(parts[0]),
              let cpu = Double(parts[1]),
              let mem = Double(parts[2])
        else {
            return nil
        }

        let path = String(parts[3]).trimmingCharacters(in: .whitespaces)
        let name = URL(fileURLWithPath: path).lastPathComponent

        return ProcessEntry(
            pid: pid,
            name: name,
            cpuPercent: cpu,
            memPercent: mem,
            ports: portsByPID[pid] ?? [],
            bundleURL: bundleURLsByPID[pid]
        )
    }

    private static func parsePorts(_ text: String) -> [Int32: [Int]] {
        var result: [Int32: Set<Int>] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("COMMAND") {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            guard cols.count >= 2, let pid = Int32(cols[1]) else { continue }

            var addressToken = String(cols[cols.count - 1])
            if addressToken == "(LISTEN)", cols.count >= 3 {
                addressToken = String(cols[cols.count - 2])
            }
            guard let portString = addressToken.split(separator: ":").last,
                  let port = Int(portString)
            else {
                continue
            }
            result[pid, default: []].insert(port)
        }
        return result.mapValues { $0.sorted() }
    }

    @MainActor
    private static func runningAppBundleURLs() -> [Int32: URL] {
        var map: [Int32: URL] = [:]
        for app in NSWorkspace.shared.runningApplications {
            if let url = app.bundleURL {
                map[app.processIdentifier] = url
            }
        }
        return map
    }

    // MARK: - Process Execution

    private static func runCommand(_ path: String, _ args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: path)
            task.arguments = args

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()

            do {
                try task.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
        }
    }
}

enum ProcessesError: LocalizedError {
    case killFailed(pid: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case let .killFailed(pid, message):
            "Failed to kill process \(pid): \(message)"
        }
    }
}
