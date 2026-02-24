import SwiftUI

struct JetBrainsAction: Action {
    let id: ActionID
    let title: String
    let subtitle: String
    let iconName: String?
    let relevanceScore: Double
    let keywords: [String]
    let parameters: [ActionParameter]

    let projectPath: String?
    let ideName: String?
    let ideTag: String?
    let isOpen: Bool
    let frameContext: String?

    private let runner:
        @Sendable ([String: Any]) async throws -> ActionResult

    init(
        id: ActionID,
        title: String,
        subtitle: String,
        iconName: String? = nil,
        relevanceScore: Double = 0.8,
        keywords: [String] = [],
        parameters: [ActionParameter] = [],
        projectPath: String? = nil,
        ideName: String? = nil,
        ideTag: String? = nil,
        isOpen: Bool = false,
        frameContext: String? = nil,
        runner: @escaping @Sendable ([String: Any]) async throws
            -> ActionResult
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.relevanceScore = relevanceScore
        self.keywords = keywords
        self.parameters = parameters
        self.projectPath = projectPath
        self.ideName = ideName
        self.ideTag = ideTag
        self.isOpen = isOpen
        self.frameContext = frameContext
        self.runner = runner
    }

    func run(
        with values: [String: Any]
    ) async throws -> ActionResult {
        try await runner(values)
    }

    @MainActor
    func makeListItemView() -> AnyView? {
        AnyView(JetBrainsActionListItemView(action: self))
    }

    @MainActor
    func makePreviewView() -> AnyView? {
        AnyView(JetBrainsActionPreviewView(action: self))
    }
}
