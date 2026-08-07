import Foundation

enum ActionResult: Sendable {
    case dismiss
    case keepOpen
    case pushActions([any Action])
    case showResult(title: String, body: String)
    case chain(ActionID, values: ParameterValues)
}
