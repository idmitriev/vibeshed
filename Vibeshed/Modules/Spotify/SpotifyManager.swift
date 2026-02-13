import AppKit
import Foundation

enum SpotifyError: Error, LocalizedError {
    case scriptFailed(String)
    case scriptTimeout
    case notRunning

    var errorDescription: String? {
        switch self {
        case .scriptFailed(let stderr): "AppleScript error: \(stderr)"
        case .scriptTimeout: "AppleScript execution timed out"
        case .notRunning: "Spotify is not running"
        }
    }
}

struct SpotifyNowPlaying: Sendable {
    let trackName: String
    let artistName: String
    let albumName: String
    let artworkURL: String
    let durationMs: Int
    let positionSeconds: Double
    let trackID: String
    let isPlaying: Bool
}

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

enum SpotifyManager {
    private static let bundleID = "com.spotify.client"

    // MARK: - State

    static func isRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    static func playerState() async throws -> String {
        let output = try await runScript("""
            tell application "Spotify" to return player state as string
            """)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Playback Control

    static func playPause() async throws {
        try await runScript("tell application \"Spotify\" to playpause")
    }

    static func nextTrack() async throws {
        try await runScript("tell application \"Spotify\" to next track")
    }

    static func previousTrack() async throws {
        try await runScript("tell application \"Spotify\" to previous track")
    }

    static func toggleShuffle() async throws {
        try await runScript("""
            tell application "Spotify"
                if shuffling then
                    set shuffling to false
                else
                    set shuffling to true
                end if
            end tell
            """)
    }

    static func toggleRepeat() async throws {
        try await runScript("""
            tell application "Spotify"
                if repeating then
                    set repeating to false
                else
                    set repeating to true
                end if
            end tell
            """)
    }

    // MARK: - Now Playing

    static func nowPlaying() async throws -> SpotifyNowPlaying? {
        let output = try await runScript("""
            tell application "Spotify"
                if player state is stopped then return ""
                set trackName to name of current track
                set artistName to artist of current track
                set albumName to album of current track
                set artURL to artwork url of current track
                set trackDuration to duration of current track
                set playerPos to player position
                set trackID to id of current track
                set pState to player state as string
                set d to "\t"
                set o to trackName & d & artistName & d & albumName
                set o to o & d & artURL & d & trackDuration
                set o to o & d & playerPos & d & trackID & d & pState
                return o
            end tell
            """)

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: "\t", maxSplits: 7, omittingEmptySubsequences: false)
        guard parts.count >= 7 else { return nil }

        return SpotifyNowPlaying(
            trackName: String(parts[0]),
            artistName: String(parts[1]),
            albumName: String(parts[2]),
            artworkURL: String(parts[3]),
            durationMs: Int(parts[4]) ?? 0,
            positionSeconds: Double(parts[5]) ?? 0,
            trackID: String(parts[6]),
            isPlaying: parts.count > 7 && String(parts[7]) == "playing"
        )
    }

    // MARK: - Open URI

    static func openURI(_ uri: String) async throws {
        let escaped = uri
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        try await runScript("""
            tell application "Spotify"
                open location "\(escaped)"
                play
            end tell
            """)
    }

    // MARK: - Private: AppleScript Execution

    @discardableResult
    private static func runScript(_ script: String) async throws -> String {
        guard isRunning() else { throw SpotifyError.notRunning }

        return try await withCheckedThrowingContinuation { continuation in
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
                gate.resume(with: .failure(SpotifyError.scriptTimeout))
                process.terminate()
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeoutWorkItem)

            process.terminationHandler = { _ in
                timeoutWorkItem.cancel()

                let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                if process.terminationStatus != 0 {
                    let errorMsg = String(data: errorData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
                    gate.resume(with: .failure(SpotifyError.scriptFailed(errorMsg)))
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
                gate.resume(with: .failure(error))
            }
        }
    }
}
