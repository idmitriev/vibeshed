import Foundation
import OSLog

private let log = Log.module("github")

/// The GitHub CLI (`gh`), for its login: when config.yaml has no token, the module asks
/// `gh auth token` for the one the user signed in with, so search, notifications and
/// open pull requests work without copying a token anywhere. The token stays in memory
/// and only goes to api.github.com.
enum GitHubCLI {
    static let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]

    /// The signed-in github.com account's token, or nil when `gh` is missing, signed out,
    /// or doesn't answer within `timeout` (say, a keychain prompt nobody answers).
    static func authToken(customPath: String?, timeout: TimeInterval = 5) async -> String? {
        guard let path = CLILauncher.resolveCLI(customPath: customPath, candidates: candidates, log: log) else {
            return nil
        }
        do {
            let output = try await run(path, ["auth", "token", "--hostname", "github.com"], timeout: timeout)
            let token = String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return token?.isEmpty == false ? token : nil
        } catch {
            log.info("No token from gh: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func run(_ path: String, _ arguments: [String], timeout: TimeInterval) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let gate = ResumeGate(continuation: continuation)
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                let timeoutWorkItem = DispatchWorkItem {
                    gate.resume(with: .failure(GitHubCLIError.timedOut))
                    process.terminate()
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

                do {
                    try process.run()
                } catch {
                    timeoutWorkItem.cancel()
                    gate.resume(with: .failure(error))
                    return
                }

                // Drain both pipes before waiting on exit (see AppleScriptRunner.run):
                // a full pipe buffer would otherwise block the tool forever.
                let readGroup = DispatchGroup()
                // Safe: readGroup.wait() below is a happens-before barrier against both writes.
                nonisolated(unsafe) var outputData = Data()
                nonisolated(unsafe) var errorData = Data()
                readGroup.enter()
                DispatchQueue.global(qos: .utility).async {
                    outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    readGroup.leave()
                }
                readGroup.enter()
                DispatchQueue.global(qos: .utility).async {
                    errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    readGroup.leave()
                }
                readGroup.wait()
                process.waitUntilExit()
                timeoutWorkItem.cancel()

                guard process.terminationStatus == 0 else {
                    let message = String(data: errorData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    gate.resume(with: .failure(GitHubCLIError.failed(message)))
                    return
                }
                gate.resume(with: .success(outputData))
            }
        }
    }
}

enum GitHubCLIError: LocalizedError {
    case timedOut
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .timedOut: "gh didn't answer in time"
        case let .failed(message): message.isEmpty ? "gh failed" : message
        }
    }
}
