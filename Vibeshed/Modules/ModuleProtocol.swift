import SwiftUI

protocol Module: Actor {
    var id: String { get }
    var displayName: String { get }
    var iconName: String { get }
    var isEnabled: Bool { get set }

    func initialize(context: ModuleContext) async throws
    func teardown() async
    func provideActions(query: String, scoring: ScoringContext) async -> [any Action]

    func provideParameterOptions(
        for parameterID: String,
        in actionID: ActionID,
        query: String
    ) async -> [ParameterOption]

    func configDidChange(_ config: AppConfig.ModuleConfig) async
}

extension Module {
    func teardown() async {}

    func provideParameterOptions(
        for parameterID: String,
        in actionID: ActionID,
        query: String
    ) async -> [ParameterOption] {
        []
    }

    func configDidChange(_ config: AppConfig.ModuleConfig) async {}
}
