import Foundation

actor MockModule: Module {
    let id = "mock"
    let displayName = "Mock Module"
    let iconName = "sparkle"
    var isEnabled = true

    private var actions: [MockAction] = []

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
}

struct MockAction: Action {
    let id: ActionID
    let title: String
    let subtitle: String
    let iconName: String?
    let relevanceScore: Double
    let keywords: [String]

    func run(with values: [String: Any]) async throws -> ActionResult {
        .dismiss
    }
}
