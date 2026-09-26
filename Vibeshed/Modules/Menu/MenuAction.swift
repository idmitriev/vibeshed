import SwiftUI

struct MenuAction: Action {
    let id: ActionID
    let title: String
    let subtitle: String
    let iconName: String?
    let appIconPath: String?
    let relevanceScore: Double
    let keywords: [String]
    let parameters: [ActionParameter]

    /// The item this action presses; nil for `menu/search`.
    let entry: MenuItemEntry?
    /// The app the menus were read from; nil when resolved from an ID alone.
    let appName: String?

    private let runner: @Sendable (ParameterValues) async throws -> ActionResult

    init(
        id: ActionID,
        title: String,
        subtitle: String,
        iconName: String?,
        appIconPath: String? = nil,
        relevanceScore: Double,
        keywords: [String] = [],
        parameters: [ActionParameter] = [],
        entry: MenuItemEntry? = nil,
        appName: String? = nil,
        runner: @escaping @Sendable (ParameterValues) async throws -> ActionResult
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.appIconPath = appIconPath
        self.relevanceScore = relevanceScore
        self.keywords = keywords
        self.parameters = parameters
        self.entry = entry
        self.appName = appName
        self.runner = runner
    }

    func run(with values: ParameterValues) async throws -> ActionResult {
        try await runner(values)
    }

    @MainActor
    func makePreviewView() -> AnyView? {
        AnyView(MenuActionPreviewView(action: self))
    }
}
