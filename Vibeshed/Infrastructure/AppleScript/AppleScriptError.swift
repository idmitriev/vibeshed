import Foundation

enum AppleScriptError: Error, LocalizedError {
    case scriptFailed(String)
    case scriptTimeout
    case appNotRunning(String)

    var errorDescription: String? {
        switch self {
        case .scriptFailed(let stderr): "AppleScript error: \(stderr)"
        case .scriptTimeout: "AppleScript execution timed out"
        case .appNotRunning(let name): "\(name) is not running"
        }
    }
}
