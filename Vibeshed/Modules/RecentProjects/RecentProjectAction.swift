import SwiftUI

/// Single action type backing every `RecentProjectsModule`. Display fields are read
/// from the carried `RecentProjectItem`; running it invokes the item's `open` closure.
struct RecentProjectAction: Action {
    let id: ActionID
    let relevanceScore: Double
    let item: RecentProjectItem

    var title: String {
        item.title
    }

    var subtitle: String {
        item.subtitle
    }

    var iconName: String? {
        item.listIcon
    }

    var keywords: [String] {
        item.keywords
    }

    var parameters: [ActionParameter] {
        []
    }

    func run(with _: ParameterValues) async throws -> ActionResult {
        item.open()
        return .dismiss
    }

    @MainActor
    func makeListItemView() -> AnyView? {
        AnyView(RecentProjectListItemView(item: item))
    }

    @MainActor
    func makePreviewView() -> AnyView? {
        AnyView(RecentProjectPreviewView(item: item, moduleID: id.moduleID))
    }
}
