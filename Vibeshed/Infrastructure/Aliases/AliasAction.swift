import AppKit
import SwiftUI

struct AliasAction: Action {
    let id: ActionID
    let title: String
    let subtitle: String
    let iconName: String?
    let relevanceScore: Double
    let keywords: [String]
    let parameters: [ActionParameter]

    private let targetActionID: ActionID
    private let prefilledParameters: [String: String]
    private let browser: String?
    private let profile: String?

    init(
        id: ActionID,
        title: String,
        subtitle: String,
        iconName: String? = nil,
        relevanceScore: Double = 0.9,
        keywords: [String] = [],
        parameters: [ActionParameter] = [],
        targetActionID: ActionID,
        prefilledParameters: [String: String] = [:],
        browser: String? = nil,
        profile: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.relevanceScore = relevanceScore
        self.keywords = keywords
        self.parameters = parameters
        self.targetActionID = targetActionID
        self.prefilledParameters = prefilledParameters
        self.browser = browser
        self.profile = profile
    }

    func run(with values: [String: Any]) async throws -> ActionResult {
        let target = targetActionID.rawValue

        // URL aliases — open in browser
        if target.hasPrefix("http://") || target.hasPrefix("https://") {
            var urlString = target
            if let query = values["query"] as? String {
                let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
                urlString = urlString.replacingOccurrences(of: "{query}", with: encoded)
            }
            guard let url = URL(string: urlString) else {
                return .showResult(title: "Error", body: "Invalid URL: \(urlString)")
            }
            if let browser {
                try BrowserRegistry.open(url: url, browser: browser, profile: profile)
            } else {
                NSWorkspace.shared.open(url)
            }
            return .dismiss
        }

        // Directory / file path aliases — open in Finder
        if target.hasPrefix("/") || target.hasPrefix("~/") {
            let expanded = NSString(string: target).expandingTildeInPath
            NSWorkspace.shared.open(URL(fileURLWithPath: expanded))
            return .dismiss
        }

        // Standard action chaining
        var merged = prefilledParameters
        // Substitute {query} placeholders with the provided query parameter
        if let query = values["query"] as? String {
            for (key, value) in merged {
                merged[key] = value.replacingOccurrences(of: "{query}", with: query)
            }
        }
        // Pass through any additional values from parameter input
        for (key, value) in values {
            if let str = value as? String, key != "query" {
                merged[key] = str
            }
        }
        return .chain(targetActionID, values: merged)
    }

    @MainActor
    func makeListItemView() -> AnyView? {
        AnyView(AliasActionListItemView(action: self))
    }

    @MainActor
    func makePreviewView() -> AnyView? {
        AnyView(AliasActionPreviewView(action: self))
    }
}
