import SwiftUI

protocol Module: Actor {
    var id: String { get }
    var displayName: String { get }
    var iconName: String { get }
    var isEnabled: Bool { get set }

    static var requiredPermissions: Set<Permission> { get }

    /// Whether `provideActions` output depends on the query text.
    ///
    /// Catalog modules (the default, `false`) ignore `query` and return their full
    /// action catalog — the picker fetches them once per session and re-scores the
    /// cached corpus on every keystroke. Query-dependent modules (`true`, e.g.
    /// `MathModule`) *compute* actions from the input and are re-queried per keystroke.
    static var isQueryDependent: Bool { get }

    func initialize(context: ModuleContext) async throws
    func teardown() async

    /// Returns the actions this module contributes to the picker.
    ///
    /// Contract: the picker performs all fuzzy filtering/ranking itself (see
    /// `ActionScorer`), so **most modules ignore `query` and return their full
    /// catalog**. The exception is modules that *compute* results from the input —
    /// e.g. `MathModule` parses `query` and returns calculated values — which may use
    /// it. `scoring` is advisory context (usage/recency/system state); modules normally
    /// don't need it since the picker applies scoring downstream.
    func provideActions(query: String, scoring: ScoringContext) async -> [any Action]

    /// Resolves a single action by ID — used by keybinding and URI execution, not by
    /// the picker list. The default scans `provideActions`; modules whose IDs are
    /// cheaply reversible may override. Note: actions that are computed from a live
    /// query (e.g. math results) are intentionally unresolvable here.
    func action(id: ActionID) async -> (any Action)?

    func provideParameterOptions(
        for parameterID: String,
        in actionID: ActionID,
        query: String
    ) async -> [ParameterOption]

    /// Live preview for parameters declared with `livePreview: true`: called (debounced)
    /// each time the highlighted option changes while the picker collects `parameterID`.
    func previewParameterOption(_ optionID: String, parameterID: String, actionID: ActionID) async

    /// Ends a live preview. `committed == false` (Escape, picker dismissed) means undo
    /// everything the previews changed; `true` means the action is about to run with the
    /// chosen value, so keep it.
    func endParameterPreview(parameterID: String, actionID: ActionID, committed: Bool) async
}

extension Module {
    static var requiredPermissions: Set<Permission> {
        []
    }

    static var isQueryDependent: Bool {
        false
    }

    func teardown() async {}

    func action(id: ActionID) async -> (any Action)? {
        let actions = await provideActions(
            query: "",
            scoring: ScoringContext(
                usageCounts: [:], lastUsedDates: [:], query: "", systemContext: nil
            )
        )
        return actions.first { $0.id == id }
    }

    func provideParameterOptions(
        for parameterID: String,
        in actionID: ActionID,
        query: String
    ) async -> [ParameterOption] {
        []
    }

    func previewParameterOption(_: String, parameterID _: String, actionID _: ActionID) async {}

    func endParameterPreview(parameterID _: String, actionID _: ActionID, committed _: Bool) async {}
}
