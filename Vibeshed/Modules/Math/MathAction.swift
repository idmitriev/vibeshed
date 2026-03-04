import SwiftUI

enum MathResultType: String, Sendable {
    case expression
    case unitConversion
    case currencyConversion
    case percentage
    case baseConversion
}

struct MathAction: Action {
    let id: ActionID
    let title: String
    let subtitle: String
    let iconName: String?
    let relevanceScore: Double
    let keywords: [String]
    let parameters: [ActionParameter]

    let resultType: MathResultType
    let formattedResult: String
    let detailLines: [(label: String, value: String)]

    private let runner: @Sendable ([String: Any]) async throws -> ActionResult

    init(
        id: ActionID,
        title: String,
        subtitle: String,
        iconName: String? = nil,
        relevanceScore: Double = 0.98,
        keywords: [String] = [],
        resultType: MathResultType = .expression,
        formattedResult: String,
        detailLines: [(label: String, value: String)] = [],
        runner: @escaping @Sendable ([String: Any]) async throws -> ActionResult
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.relevanceScore = relevanceScore
        self.keywords = keywords
        self.parameters = []
        self.resultType = resultType
        self.formattedResult = formattedResult
        self.detailLines = detailLines
        self.runner = runner
    }

    func run(with values: [String: Any]) async throws -> ActionResult {
        try await runner(values)
    }

    @MainActor
    func makeListItemView() -> AnyView? {
        AnyView(MathActionListItemView(action: self))
    }

    @MainActor
    func makePreviewView() -> AnyView? {
        AnyView(MathActionPreviewView(action: self))
    }
}
