import SwiftUI

struct BookmarkAction: Action {
    let id: ActionID
    let title: String
    let subtitle: String
    let iconName: String?
    let relevanceScore: Double
    let keywords: [String]
    let parameters: [ActionParameter]

    private let runner: @Sendable ([String: Any]) async throws -> ActionResult
    let browserBundleID: String?
    let url: String?
    let visitCount: Int?
    let folderPath: String?

    init(
        id: ActionID,
        title: String,
        subtitle: String,
        iconName: String? = nil,
        relevanceScore: Double = 0.6,
        keywords: [String] = [],
        parameters: [ActionParameter] = [],
        browserBundleID: String? = nil,
        url: String? = nil,
        visitCount: Int? = nil,
        folderPath: String? = nil,
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
        self.url = url
        self.visitCount = visitCount
        self.folderPath = folderPath
        self.runner = runner
    }

    func run(with values: [String: Any]) async throws -> ActionResult {
        try await runner(values)
    }

    @MainActor
    func makeListItemView() -> AnyView? {
        AnyView(BookmarkActionListItemView(action: self))
    }

    @MainActor
    func makePreviewView() -> AnyView? {
        AnyView(BookmarkActionPreviewView(action: self))
    }
}

extension BookmarkAction {
    @MainActor
    var browserIcon: NSImage? {
        guard let bundleID = browserBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
