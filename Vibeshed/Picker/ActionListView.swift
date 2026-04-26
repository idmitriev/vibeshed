import SwiftUI

struct ActionListView: View {
    let actions: [ActionItem]
    @Binding var selectedID: ActionID?
    var actionCache: [ActionID: any Action] = [:]
    var onActivate: ((ActionID) -> Void)?
    @Environment(\.vibeTheme) private var theme

    /// Map first 9 action IDs → hotkey number (1-9) for O(1) lookup per row.
    private var hotkeyMap: [ActionID: Int] {
        var map = [ActionID: Int]()
        map.reserveCapacity(min(actions.count, 9))
        for i in 0 ..< min(actions.count, 9) {
            map[actions[i].id] = i + 1
        }
        return map
    }

    var body: some View {
        let hotkeys = hotkeyMap
        ScrollViewReader { proxy in
            List(selection: $selectedID) {
                ForEach(actions) { item in
                    let singleClick = actionCache[item.id]?.activatesOnSingleClick ?? false
                    actionRow(for: item, hotkeyNumber: hotkeys[item.id])
                        .tag(item.id)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            selectedID = item.id
                            if !singleClick {
                                onActivate?(item.id)
                            }
                        }
                        .onTapGesture(count: 1) {
                            selectedID = item.id
                            if singleClick {
                                onActivate?(item.id)
                            }
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .tint(theme.accent)
            .accessibilityIdentifier("actionList")
            .onChange(of: selectedID) { _, newID in
                if let newID {
                    proxy.scrollTo(newID, anchor: nil)
                }
            }
        }
    }

    @ViewBuilder
    private func actionRow(for item: ActionItem, hotkeyNumber: Int?) -> some View {
        if let action = actionCache[item.id],
           let customView = action.makeListItemView() {
            customView
        } else {
            ActionListItemView(item: item, hotkeyNumber: hotkeyNumber)
        }
    }
}
