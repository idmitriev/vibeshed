import AppKit
import SwiftUI

struct URLChooserAction: Action {
    let id: ActionID
    let title: String
    let subtitle: String
    let iconName: String?
    let relevanceScore: Double
    let keywords: [String]
    let parameters: [ActionParameter] = []

    let browserBundleID: String
    let profileDirectory: String?

    private let runner: @Sendable ([String: Any]) async throws -> ActionResult

    init(
        id: ActionID,
        title: String,
        subtitle: String,
        iconName: String? = nil,
        relevanceScore: Double = 0.8,
        keywords: [String] = [],
        browserBundleID: String,
        profileDirectory: String? = nil,
        runner: @escaping @Sendable ([String: Any]) async throws -> ActionResult
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.relevanceScore = relevanceScore
        self.keywords = keywords
        self.browserBundleID = browserBundleID
        self.profileDirectory = profileDirectory
        self.runner = runner
    }

    func run(with values: [String: Any]) async throws -> ActionResult {
        try await runner(values)
    }

    @MainActor
    func makeListItemView() -> AnyView? {
        AnyView(URLChooserListItemView(action: self))
    }

    @MainActor
    func makePreviewView() -> AnyView? {
        AnyView(URLChooserPreviewView(action: self))
    }
}

extension URLChooserAction {
    @MainActor
    var browserIcon: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: browserBundleID
        ) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
