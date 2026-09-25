import SwiftUI

enum ITermItemType: String, Sendable {
    case session
    case newTab
    case newWindow
    case command
}

/// What a session's shell is doing: idle at its prompt, or running a job.
enum ITermShellState: Sendable {
    case atPrompt
    case runningJob
}

struct ITermAction: Action {
    let id: ActionID
    let title: String
    let subtitle: String
    let iconName: String?
    let relevanceScore: Double
    let keywords: [String]
    let parameters: [ActionParameter]

    let itermItemType: ITermItemType?
    let sessionPath: String?
    let jobName: String?
    let profileName: String?
    /// Set for session rows only.
    let shellState: ITermShellState?

    private let runner: @Sendable (
        ParameterValues
    ) async throws -> ActionResult

    init(
        id: ActionID,
        title: String,
        subtitle: String,
        iconName: String? = nil,
        relevanceScore: Double = 0.8,
        keywords: [String] = [],
        parameters: [ActionParameter] = [],
        itermItemType: ITermItemType? = nil,
        sessionPath: String? = nil,
        jobName: String? = nil,
        profileName: String? = nil,
        shellState: ITermShellState? = nil,
        runner: @escaping @Sendable (
            ParameterValues
        ) async throws -> ActionResult
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.relevanceScore = relevanceScore
        self.keywords = keywords
        self.parameters = parameters
        self.itermItemType = itermItemType
        self.sessionPath = sessionPath
        self.jobName = jobName
        self.profileName = profileName
        self.shellState = shellState
        self.runner = runner
    }

    func run(
        with values: ParameterValues
    ) async throws -> ActionResult {
        try await runner(values)
    }

    @MainActor
    func makeListItemView() -> AnyView? {
        AnyView(ITermActionListItemView(action: self))
    }

    @MainActor
    func makePreviewView() -> AnyView? {
        AnyView(ITermActionPreviewView(action: self))
    }
}
