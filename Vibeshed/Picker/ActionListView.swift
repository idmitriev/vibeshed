import SwiftUI

struct ActionListView: View {
    let actions: [ActionItem]
    @Binding var selectedID: ActionID?

    var body: some View {
        List(actions, selection: $selectedID) { item in
            ActionListItemView(item: item)
                .tag(item.id)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("actionList")
    }
}
