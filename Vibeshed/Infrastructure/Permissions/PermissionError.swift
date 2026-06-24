import Foundation

enum PermissionError: Error, LocalizedError {
    case denied(moduleID: String, permissions: Set<Permission>)

    var errorDescription: String? {
        switch self {
        case let .denied(id, permissions):
            "Module '\(id)' requires permissions: \(permissions.map(\.displayName).sorted().joined(separator: ", "))"
        }
    }

    var grantInstructions: [String] {
        switch self {
        case let .denied(_, permissions):
            permissions.sorted(by: { $0.rawValue < $1.rawValue }).map { permission in
                "\(permission.displayName): \(permission.grantInstructions)"
            }
        }
    }
}
