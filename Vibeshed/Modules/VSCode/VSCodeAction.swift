import SwiftUI

enum VSCodeItemType: String, Sendable {
    case project
    case file
    case remote
}

struct VSCodeAction: Action {
    let id: ActionID
    let title: String
    let subtitle: String
    let iconName: String?
    let relevanceScore: Double
    let keywords: [String]
    let parameters: [ActionParameter]

    let projectPath: String?
    let vscodeItemType: VSCodeItemType?
    let variant: String?

    private let runner: @Sendable ([String: Any]) async throws -> ActionResult

    init(
        id: ActionID,
        title: String,
        subtitle: String,
        iconName: String? = nil,
        relevanceScore: Double = 0.8,
        keywords: [String] = [],
        parameters: [ActionParameter] = [],
        projectPath: String? = nil,
        vscodeItemType: VSCodeItemType? = nil,
        variant: String? = nil,
        runner: @escaping @Sendable ([String: Any]) async throws -> ActionResult
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.relevanceScore = relevanceScore
        self.keywords = keywords
        self.parameters = parameters
        self.projectPath = projectPath
        self.vscodeItemType = vscodeItemType
        self.variant = variant
        self.runner = runner
    }

    func run(with values: [String: Any]) async throws -> ActionResult {
        try await runner(values)
    }

    @MainActor
    func makeListItemView() -> AnyView? {
        AnyView(VSCodeActionListItemView(action: self))
    }

    @MainActor
    func makePreviewView() -> AnyView? {
        AnyView(VSCodeActionPreviewView(action: self))
    }
}
