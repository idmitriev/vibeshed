import Foundation

enum ModuleConfigError: Error, LocalizedError {
    case decodingFailed(moduleID: String, underlying: Error)
    case validationFailed(moduleID: String, reasons: [String])
    case missingRequired(moduleID: String)

    var errorDescription: String? {
        switch self {
        case .decodingFailed(let id, let err):
            "Module '\(id)' config decode error: \(err.localizedDescription)"
        case .validationFailed(let id, let reasons):
            "Module '\(id)' config invalid: \(reasons.joined(separator: "; "))"
        case .missingRequired(let id):
            "Module '\(id)' requires config but none provided"
        }
    }
}

struct ConfigValidationResult: Sendable {
    let isValid: Bool
    let errors: [String]

    static let valid = ConfigValidationResult(isValid: true, errors: [])

    static func invalid(_ errors: [String]) -> ConfigValidationResult {
        ConfigValidationResult(isValid: false, errors: errors)
    }
}

protocol ModuleConfigurable: Module {
    associatedtype Config: Codable & Sendable & Equatable

    static var defaultConfig: Config? { get }
    static func validate(_ config: Config) -> ConfigValidationResult
    func configDidUpdate(_ config: Config) async
}

extension ModuleConfigurable {
    static func validate(_: Config) -> ConfigValidationResult { .valid }
    func configDidUpdate(_: Config) async {}
}
