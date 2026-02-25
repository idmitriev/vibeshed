import SwiftUI

struct ActionListView: View {
    let actions: [ActionItem]
    @Binding var selectedID: ActionID?
    var actionCache: [ActionID: any Action] = [:]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                List(selection: $selectedID) {
                    ForEach(Array(actions.enumerated()), id: \.element.id) { index, item in
                        if let action = actionCache[item.id],
                           let customView = action.makeListItemView() {
                            customView.tag(item.id)
                        } else {
                            ActionListItemView(
                                item: item,
                                hotkeyNumber: index < 9 ? index + 1 : nil
                            )
                            .tag(item.id)
                        }
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

            if actions.count > 20 {
                HStack {
                    Spacer()
                    Text("\(actions.count) items")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }
                .background(.ultraThinMaterial.opacity(0.5))
            }
        }
    }
}
