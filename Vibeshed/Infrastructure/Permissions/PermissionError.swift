import Foundation

enum PermissionError: Error, LocalizedError {
    case denied(moduleID: String, permissions: Set<Permission>)

    var errorDescription: String? {
        switch self {
        case .denied(let id, let permissions):
            "Module '\(id)' requires permissions: \(permissions.map(\.displayName).sorted().joined(separator: ", "))"
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
