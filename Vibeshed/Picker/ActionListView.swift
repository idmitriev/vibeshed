import SwiftUI

struct ActionListView: View {
    let actions: [ActionItem]
    @Binding var selectedID: ActionID?
    var actionCache: [ActionID: any Action] = [:]

    var body: some View {
        ScrollViewReader { proxy in
            List(actions, selection: $selectedID) { item in
                if let action = actionCache[item.id],
                   let customView = action.makeListItemView() {
                    customView.tag(item.id)
                } else {
                    ActionListItemView(item: item)
                        .tag(item.id)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("actionList")
            .onChange(of: selectedID) { _, newID in
                if let newID {
                    proxy.scrollTo(newID, anchor: nil)
                }
            }
        }
    }
}
