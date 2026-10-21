import Foundation

enum Shell {
    struct Failure: Error, CustomStringConvertible {
        var command: [String]
        var status: Int32
        var output: String

        var description: String {
            let tail = output.isEmpty ? "" : ":\n\(output.trimmingCharacters(in: .whitespacesAndNewlines))"
            return "`\(command.joined(separator: " "))` exited with \(status)\(tail)"
        }
    }

    /// Runs a command with this process's stdin/stdout/stderr, so its output
    /// streams straight to the terminal (or the agent's log).
    @discardableResult
    static func run(_ command: [String], in directory: URL? = nil, check: Bool = true) throws -> Int32 {
        let process = try makeProcess(command)
        process.currentDirectoryURL = directory
        try process.run()
        process.waitUntilExit()
        if check, process.terminationStatus != 0 {
            throw Failure(command: command, status: process.terminationStatus, output: "")
        }
        return process.terminationStatus
    }

    /// Runs a command and returns its stdout and stderr, combined.
    @discardableResult
    static func capture(_ command: [String], environment: [String: String] = [:], check: Bool = true) throws -> String {
        let process = try makeProcess(command)
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        try process.run()
        // Drain before waiting: a full pipe (64KB) would block the child forever.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(bytes: data, encoding: .utf8) ?? ""
        if check, process.terminationStatus != 0 {
            throw Failure(command: command, status: process.terminationStatus, output: output)
        }
        return output
    }

    static func which(_ tool: String) -> String? {
        let output = try? capture(["/usr/bin/which", tool], check: false)
        let path = output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    private static func makeProcess(_ command: [String]) throws -> Process {
        guard let executable = command.first else {
            throw Failure(command: command, status: -1, output: "empty command")
        }
        let process = Process()
        if executable.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = Array(command.dropFirst())
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = command
        }
        return process
    }
}

/// Lines prefixed with the time since launch, so a take's log lines up with
/// its recording.
enum Log {
    nonisolated(unsafe) static var start = Date()

    static func info(_ message: String) {
        let elapsed = String(format: "%7.2f", Date().timeIntervalSince(start))
        print("[\(elapsed)] \(message)")
        fflush(stdout)
    }

    static func warn(_ message: String) {
        info("⚠️  \(message)")
    }
}
