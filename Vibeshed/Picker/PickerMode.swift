import Foundation

enum PickerMode: Equatable, Hashable {
    case search
    case parameterInput(actionID: ActionID, parameterIndex: Int)
    case pushedActions

    var isParameterStep: Bool {
        if case .parameterInput = self { true } else { false }
    }
}
