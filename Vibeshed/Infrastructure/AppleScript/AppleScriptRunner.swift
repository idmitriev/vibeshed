import Foundation
import OSLog

private let log = Log.module("applescript")

enum AppleScriptRunner {

    // MARK: - Async (with timeout + continuation)

    @discardableResult
    static func run(_ script: String, timeout: TimeInterval = 5) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")

            let inputPipe = Pipe()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardInput = inputPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let gate = ResumeGate(continuation: continuation)

            let timeoutWorkItem = DispatchWorkItem {
                log.warning("AppleScript timed out after \(timeout, privacy: .public)s")
                gate.resume(with: .failure(AppleScriptError.scriptTimeout))
                process.terminate()
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

            process.terminationHandler = { _ in
                timeoutWorkItem.cancel()

                let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                if process.terminationStatus != 0 {
                    let errorMsg = String(data: errorData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
                    log.error("AppleScript failed (exit \(process.terminationStatus, privacy: .public)): \(errorMsg, privacy: .public)")
                    gate.resume(with: .failure(AppleScriptError.scriptFailed(errorMsg)))
                } else {
                    let output = String(data: outputData, encoding: .utf8) ?? ""
                    gate.resume(with: .success(output))
                }
            }

            do {
                try process.run()
                inputPipe.fileHandleForWriting.write(script.data(using: .utf8) ?? Data())
                inputPipe.fileHandleForWriting.closeFile()
            } catch {
                timeoutWorkItem.cancel()
                log.error("Failed to launch osascript: \(error.localizedDescription, privacy: .public)")
                gate.resume(with: .failure(error))
            }
        }
    }

    // MARK: - Sync (fire-and-forget, checks exit status)

    static func runSync(_ source: String) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", source]
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            log.error("AppleScript exited with status \(task.terminationStatus, privacy: .public)")
        }
    }

    // MARK: - Sync with output

    static func runSyncWithOutput(_ source: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", source]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            log.warning("osascript launch failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - ResumeGate

/// Thread-safe one-shot gate for resuming a continuation exactly once.
private final class ResumeGate<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    private let continuation: CheckedContinuation<T, Error>

    init(continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<T, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        continuation.resume(with: result)
    }
}
