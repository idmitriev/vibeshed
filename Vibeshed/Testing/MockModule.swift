import Foundation

actor MockModule: Module {
    let id = "mock"
    let displayName = "Mock Module"
    let iconName = "sparkle"
    var isEnabled = true

    private var actions: [MockAction] = []

    private let dynamicOptions: [ParameterOption] = [
        ParameterOption(id: "win1", label: "Safari — Main Window", iconName: "macwindow"),
        ParameterOption(id: "win2", label: "Xcode — Editor", iconName: "macwindow"),
        ParameterOption(id: "win3", label: "Terminal — zsh", iconName: "macwindow"),
    ]

    func initialize(context: ModuleContext) async throws {
        actions = [
            MockAction(
                id: ActionID(module: "mock", name: "safari"),
                title: "Open Safari",
                subtitle: "Launch Safari browser",
                iconName: "safari",
                relevanceScore: 1.0,
                keywords: ["safari", "browser", "web"]
            ),
            MockAction(
                id: ActionID(module: "mock", name: "calculator"),
                title: "Calculator",
                subtitle: "Open Calculator app",
                iconName: "plus.forwardslash.minus",
                relevanceScore: 0.9,
                keywords: ["calculator", "math"]
            ),
            MockAction(
                id: ActionID(module: "mock", name: "notes"),
                title: "Notes",
                subtitle: "Open Notes app",
                iconName: "note.text",
                relevanceScore: 0.8,
                keywords: ["notes", "text", "write"]
            ),
            MockAction(
                id: ActionID(module: "mock", name: "terminal"),
                title: "Terminal",
                subtitle: "Open Terminal app",
                iconName: "terminal",
                relevanceScore: 0.7,
                keywords: ["terminal", "shell", "command"]
            ),
            MockAction(
                id: ActionID(module: "mock", name: "activity"),
                title: "Activity Monitor",
                subtitle: "Open Activity Monitor",
                iconName: "chart.bar",
                relevanceScore: 0.6,
                keywords: ["activity", "monitor", "cpu", "memory"]
            ),
            // Action that shows a result view on execution
            MockAction(
                id: ActionID(module: "mock", name: "showResult"),
                title: "Show Result",
                subtitle: "Displays a result view",
                iconName: "checkmark.seal",
                relevanceScore: 0.55,
                keywords: ["result", "test"],
                result: .showResult(title: "Done", body: "Action completed successfully")
            ),
            // Action with a static selection parameter
            MockAction(
                id: ActionID(module: "mock", name: "theme"),
                title: "Set Theme",
                subtitle: "Change the app theme",
                iconName: "paintbrush",
                relevanceScore: 0.5,
                keywords: ["theme", "color", "appearance"],
                parameters: [
                    ActionParameter(
                        id: "theme",
                        label: "Theme",
                        type: .selection([
                            ParameterOption(id: "light", label: "Light", iconName: "sun.max"),
                            ParameterOption(id: "dark", label: "Dark", iconName: "moon"),
                            ParameterOption(id: "auto", label: "Auto", iconName: "circle.lefthalf.filled"),
                        ]),
                        isRequired: true
                    ),
                ]
            ),
            // Action with a dynamic selection parameter
            MockAction(
                id: ActionID(module: "mock", name: "focusWindow"),
                title: "Focus Window",
                subtitle: "Focus a specific window",
                iconName: "macwindow",
                relevanceScore: 0.5,
                keywords: ["focus", "window", "switch"],
                parameters: [
                    ActionParameter(
                        id: "window",
                        label: "Select a window",
                        type: .dynamicSelection(hint: "window"),
                        isRequired: true
                    ),
                ]
            ),
        ]
    }

    func provideActions(query: String, scoring: ScoringContext) async -> [any Action] {
        guard !query.isEmpty else { return actions }
        let lowered = query.lowercased()
        return actions.filter { action in
            action.title.lowercased().contains(lowered)
                || action.subtitle.lowercased().contains(lowered)
                || action.keywords.contains(where: { $0.contains(lowered) })
        }
    }

    func provideParameterOptions(
        for parameterID: String,
        in _: ActionID,
        query: String
    ) async -> [ParameterOption] {
        guard parameterID == "window" else { return [] }
        guard !query.isEmpty else { return dynamicOptions }
        let lowered = query.lowercased()
        return dynamicOptions.filter { $0.label.lowercased().contains(lowered) }
    }
}

struct MockAction: Action {
    let id: ActionID
    let title: String
    let subtitle: String
    let iconName: String?
    let relevanceScore: Double
    let keywords: [String]
    var parameters: [ActionParameter] = []
    var result: ActionResult = .dismiss

    func run(with values: [String: Any]) async throws -> ActionResult {
        result
    }
}
