import Foundation

enum PermissionError: Error, LocalizedError {
    case denied(moduleID: String, permissions: Set<Permission>)

    var errorDescription: String? {
        switch self {
        case .denied(let id, let permissions):
            let names = permissions.map(\.displayName).sorted().joined(separator: ", ")
            return "Module '\(id)' requires permissions: \(names)"
        }
    }

    var grantInstructions: [String] {
        switch self {
        case .denied(_, let permissions):
            permissions.sorted(by: { $0.rawValue < $1.rawValue }).map { permission in
                "\(permission.displayName): \(permission.grantInstructions)"
            }
        }
    }
}
