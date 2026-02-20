import SwiftUI

struct WindowAction: Action {
    let id: ActionID
    let title: String
    let subtitle: String
    let iconName: String?
    let relevanceScore: Double
    let keywords: [String]
    let parameters: [ActionParameter]

    let windowID: Int?
    let appBundleID: String?

    private let runner: @Sendable ([String: Any]) async throws -> ActionResult

    init(
        id: ActionID,
        title: String,
        subtitle: String,
        iconName: String? = nil,
        relevanceScore: Double = 0.8,
        keywords: [String] = [],
        parameters: [ActionParameter] = [],
        windowID: Int? = nil,
        appBundleID: String? = nil,
        runner: @escaping @Sendable ([String: Any]) async throws -> ActionResult
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.relevanceScore = relevanceScore
        self.keywords = keywords
        self.parameters = parameters
        self.windowID = windowID
        self.appBundleID = appBundleID
        self.runner = runner
    }

    func run(with values: [String: Any]) async throws -> ActionResult {
        try await runner(values)
    }

    @MainActor
    func makeListItemView() -> AnyView? {
        AnyView(WindowActionListItemView(action: self))
    }

    @MainActor
    func makePreviewView() -> AnyView? {
        AnyView(WindowActionPreviewView(action: self))
    }
}
