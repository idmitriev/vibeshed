import Foundation
import OSLog

private let log = Log.module("performance")

struct ProcessUsage: Sendable, Equatable, Identifiable {
    var pid: Int32
    var name: String
    /// Share of one core, as `ps` and Activity Monitor report it (can exceed 100).
    var cpuPercent: Double
    var residentBytes: UInt64

    var id: Int32 {
        pid
    }
}

/// Every process's CPU and memory use, from `ps`. It is setuid root, so unlike
/// `proc_pidinfo` it sees other users' processes (WindowServer, kernel_task, daemons).
enum TopProcesses {
    static func fetch() async -> [ProcessUsage] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: parse(runPS()))
            }
        }
    }

    /// Parses `ps -Aco pid=,pcpu=,rss=,comm=` output (RSS in KiB; names may contain spaces).
    static func parse(_ output: String) -> [ProcessUsage] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4,
                  let pid = Int32(fields[0]),
                  let cpu = Double(fields[1].replacingOccurrences(of: ",", with: ".")),
                  let rss = UInt64(fields[2])
            else {
                return nil
            }
            return ProcessUsage(
                pid: pid,
                name: fields[3].trimmingCharacters(in: .whitespaces),
                cpuPercent: cpu,
                residentBytes: rss * 1024
            )
        }
    }

    private static func runPS() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-Aco", "pid=,pcpu=,rss=,comm="]
        // ps formats %CPU with the locale's decimal separator.
        process.environment = ["LC_ALL": "en_US.UTF-8"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            log.warning("ps failed: \(error.localizedDescription, privacy: .public)")
            return ""
        }
        // Drain before waiting: waitUntilExit() first deadlocks past the 64KB pipe buffer.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(bytes: data, encoding: .utf8) ?? ""
    }
}
