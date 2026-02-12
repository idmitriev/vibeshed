import SwiftUI

struct FavouritesAction: Action {
    let id: ActionID
    let title: String
    let subtitle: String
    let iconName: String?
    let relevanceScore: Double
    let keywords: [String]
    let parameters: [ActionParameter]

    private let targetActionID: ActionID
    private let prefilledParameters: [String: String]

    init(
        id: ActionID,
        title: String,
        subtitle: String,
        iconName: String? = nil,
        relevanceScore: Double = 0.9,
        keywords: [String] = [],
        parameters: [ActionParameter] = [],
        targetActionID: ActionID,
        prefilledParameters: [String: String] = [:]
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
    }

    func run(with values: [String: Any]) async throws -> ActionResult {
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
        AnyView(FavouritesActionListItemView(action: self))
    }

    @MainActor
    func makePreviewView() -> AnyView? {
        AnyView(FavouritesActionPreviewView(action: self))
    }
}
