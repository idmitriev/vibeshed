import Foundation

enum PickerMode: Equatable, Hashable {
    case search
    case parameterInput(actionID: ActionID, parameterIndex: Int)
    case pushedActions
}
