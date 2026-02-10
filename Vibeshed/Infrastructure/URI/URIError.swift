import Foundation

enum URIError: Error, LocalizedError {
    case invalidURI(String, reason: String)
    case invalidRoutingRule(pattern: String, reason: String)
    case browserNotFound(String)
    case actionNotFound(ActionID)

    var errorDescription: String? {
        switch self {
        case let .invalidURI(uri, reason):
            "Invalid URI '\(uri)': \(reason)"
        case let .invalidRoutingRule(pattern, reason):
            "Invalid routing rule '\(pattern)': \(reason)"
        case let .browserNotFound(browser):
            "Browser not found: \(browser)"
        case let .actionNotFound(actionID):
            "Action not found: \(actionID)"
        }
    }
}
