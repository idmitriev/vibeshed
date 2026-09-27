import SwiftUI

struct GhosttyAction: Action {
    let id: ActionID
    let title: String
    let subtitle: String
    let iconName: String?
    let appIconPath: String?
    let relevanceScore: Double
    let keywords: [String]
    let parameters: [ActionParameter]

    /// Set for rows that focus an open terminal.
    let terminal: GhosttyTerminal?

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
        terminal: GhosttyTerminal? = nil,
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
        self.terminal = terminal
        self.runner = runner
    }

    func run(with values: ParameterValues) async throws -> ActionResult {
        try await runner(values)
    }

    @MainActor
    func makePreviewView() -> AnyView? {
        guard let terminal else { return nil }
        return AnyView(GhosttyTerminalPreviewView(action: self, terminal: terminal))
    }
}

struct GhosttyTerminalPreviewView: View {
    let action: GhosttyAction
    let terminal: GhosttyTerminal

    var body: some View {
        PreviewLayout(moduleName: "ghostty") {
            PreviewHeader(title: action.title, subtitle: action.subtitle) {
                Group {
                    if let path = action.appIconPath {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "terminal")
                            .font(.system(size: 56))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 72, height: 72)
            }

            VStack(alignment: .leading, spacing: 8) {
                if let directory = terminal.workingDirectory {
                    PreviewMetadataRow(icon: "folder", label: "Directory", value: abbreviatePath(directory))
                }
                PreviewMetadataRow(icon: "macwindow", label: "Location", value: terminal.location)
            }
        }
    }
}
