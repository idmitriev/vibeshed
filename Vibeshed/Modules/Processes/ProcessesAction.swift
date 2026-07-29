import SwiftUI

struct ProcessesAction: Action {
    let id: ActionID
    let title: String
    let subtitle: String
    let iconName: String?
    let relevanceScore: Double
    let keywords: [String]
    let parameters: [ActionParameter]

    let pid: Int32

    private let appBundleURL: URL?
    private let runner: @Sendable (ParameterValues) async throws -> ActionResult

    init(
        id: ActionID,
        title: String,
        subtitle: String,
        iconName: String? = nil,
        relevanceScore: Double = 0.5,
        keywords: [String] = [],
        parameters: [ActionParameter] = [],
        pid: Int32,
        appBundleURL: URL? = nil,
        runner: @escaping @Sendable (ParameterValues) async throws -> ActionResult
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.relevanceScore = relevanceScore
        self.keywords = keywords
        self.parameters = parameters
        self.pid = pid
        self.appBundleURL = appBundleURL
        self.runner = runner
    }

    func run(with values: ParameterValues) async throws -> ActionResult {
        try await runner(values)
    }

    @MainActor
    func makeListItemView() -> AnyView? {
        AnyView(ProcessesActionListItemView(action: self))
    }

    @MainActor
    func makePreviewView() -> AnyView? {
        AnyView(ProcessesActionPreviewView(action: self))
    }
}

extension ProcessesAction {
    var appIconPath: String? {
        appBundleURL?.path
    }

    @MainActor
    var appIcon: NSImage? {
        guard let url = appBundleURL else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
