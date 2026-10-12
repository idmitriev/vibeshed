import SwiftUI

struct NotesAction: Action {
    let id: ActionID
    let title: String
    let subtitle: String
    let iconName: String?
    let appIconPath: String?
    let relevanceScore: Double
    let keywords: [String]
    let parameters: [ActionParameter]
    /// The note a row opens, for its preview.
    let note: NoteInfo?

    private let runner: @Sendable (ParameterValues) async throws -> ActionResult

    init(
        id: ActionID,
        title: String,
        subtitle: String,
        iconName: String?,
        appIconPath: String?,
        relevanceScore: Double,
        keywords: [String] = [],
        parameters: [ActionParameter] = [],
        note: NoteInfo? = nil,
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
        self.note = note
        self.runner = runner
    }

    func run(with values: ParameterValues) async throws -> ActionResult {
        try await runner(values)
    }

    @MainActor
    func makePreviewView() -> AnyView? {
        note.map { AnyView(NotePreviewView(note: $0)) }
    }
}
