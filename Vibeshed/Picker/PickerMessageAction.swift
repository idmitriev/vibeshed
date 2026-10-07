import SwiftUI

/// An action's result or failure, shown as the picker's only row when it couldn't be
/// posted as a notification (see `PickerCoordinator.showMessage`). Return dismisses it.
struct PickerMessageAction: Action {
    let id: ActionID
    let title: String
    let body: String
    let isFailure: Bool

    /// `source` is the action that produced the message; the row takes its module so the
    /// preview names where it came from.
    init(source: ActionID, title: String, body: String, isFailure: Bool) {
        id = ActionID(module: source.moduleID, name: "message")
        self.title = title
        self.body = body
        self.isFailure = isFailure
    }

    var subtitle: String {
        body
    }

    var iconName: String? {
        isFailure ? "exclamationmark.triangle" : "info.circle"
    }

    var relevanceScore: Double {
        0
    }

    var activatesOnSingleClick: Bool {
        true
    }

    func run(with _: ParameterValues) async throws -> ActionResult {
        .dismiss
    }

    @MainActor
    func makePreviewView() -> AnyView? {
        AnyView(
            PreviewLayout(moduleName: id.moduleID) {
                PreviewHeader(
                    title: title,
                    subtitle: "",
                    systemIcon: iconName ?? "info.circle",
                    iconColor: isFailure ? .orange : Color.primary.opacity(0.5)
                )

                Text(body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        )
    }
}
