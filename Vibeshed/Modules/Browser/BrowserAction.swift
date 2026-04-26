import SwiftUI

struct BrowserAction: Action {
    let id: ActionID
    let title: String
    let subtitle: String
    let iconName: String?
    let relevanceScore: Double
    let keywords: [String]
    let parameters: [ActionParameter]

    private let runner: @Sendable ([String: Any]) async throws -> ActionResult
    let browserBundleID: String?
    let tabURL: String?

    init(
        id: ActionID,
        title: String,
        subtitle: String,
        iconName: String? = nil,
        relevanceScore: Double = 0.8,
        keywords: [String] = [],
        parameters: [ActionParameter] = [],
        browserBundleID: String? = nil,
        tabURL: String? = nil,
        runner: @escaping @Sendable ([String: Any]) async throws -> ActionResult
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.relevanceScore = relevanceScore
        self.keywords = keywords
        self.parameters = parameters
        self.browserBundleID = browserBundleID
        self.tabURL = tabURL
        self.runner = runner
    }

    func run(with values: [String: Any]) async throws -> ActionResult {
        try await runner(values)
    }

    var activatesOnSingleClick: Bool { true }

    @MainActor
    func makeListItemView() -> AnyView? {
        AnyView(BrowserActionListItemView(action: self))
    }

    @MainActor
    func makePreviewView() -> AnyView? {
        AnyView(BrowserActionPreviewView(action: self))
    }
}

extension BrowserAction {
    @MainActor
    var browserIcon: NSImage? {
        guard let bundleID = browserBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
