import Foundation

enum AppleScriptError: Error, LocalizedError {
    case scriptFailed(String)
    case scriptTimeout
    case appNotRunning(String)

    var errorDescription: String? {
        switch self {
        case let .scriptFailed(stderr): "AppleScript error: \(stderr)"
        case .scriptTimeout: "AppleScript execution timed out"
        case let .appNotRunning(name): "\(name) is not running"
        }
    }
}
