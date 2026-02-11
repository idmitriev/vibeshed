import SwiftUI

struct ApplicationAction: Action {
    let id: ActionID
    let title: String
    let subtitle: String
    let iconName: String?
    let relevanceScore: Double
    let keywords: [String]
    let parameters: [ActionParameter]

    private let runner: @Sendable ([String: Any]) async throws -> ActionResult
    private let appBundleURL: URL?

    init(
        id: ActionID,
        title: String,
        subtitle: String,
        iconName: String? = nil,
        relevanceScore: Double = 0.8,
        keywords: [String] = [],
        parameters: [ActionParameter] = [],
        appBundleURL: URL? = nil,
        runner: @escaping @Sendable ([String: Any]) async throws -> ActionResult
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.relevanceScore = relevanceScore
        self.keywords = keywords
        self.parameters = parameters
        self.appBundleURL = appBundleURL
        self.runner = runner
    }

    func run(with values: [String: Any]) async throws -> ActionResult {
        try await runner(values)
    }

    @MainActor
    func makeListItemView() -> AnyView? {
        AnyView(ApplicationActionListItemView(action: self))
    }

    @MainActor
    func makePreviewView() -> AnyView? {
        AnyView(ApplicationActionPreviewView(action: self))
    }
}

extension ApplicationAction {
    @MainActor
    var appIcon: NSImage? {
        guard let url = appBundleURL else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
