import SwiftUI

protocol Module: Actor {
    var id: String { get }
    var displayName: String { get }
    var iconName: String { get }
    var isEnabled: Bool { get set }

    static var requiredPermissions: Set<Permission> { get }

    func initialize(context: ModuleContext) async throws
    func teardown() async
    func provideActions(query: String, scoring: ScoringContext) async -> [any Action]

    func provideParameterOptions(
        for parameterID: String,
        in actionID: ActionID,
        query: String
    ) async -> [ParameterOption]
}

extension Module {
    static var requiredPermissions: Set<Permission> { [] }

    func teardown() async {}

    func provideParameterOptions(
        for parameterID: String,
        in actionID: ActionID,
        query: String
    ) async -> [ParameterOption] {
        []
    }
}
