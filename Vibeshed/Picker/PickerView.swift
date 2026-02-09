import SwiftUI
import Combine

struct PickerView: View {
    @Bindable var state: PickerState
    let panelController: PanelController

    var body: some View {
        VStack(spacing: 0) {
            PickerSearchField(text: $state.query)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            if state.isLoading && state.actions.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if state.actions.isEmpty && !state.query.isEmpty {
                ContentUnavailableView.search(text: state.query)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    ActionListView(
                        actions: state.actions,
                        selectedID: $state.selectedActionID
                    )
                    .frame(minWidth: 280, idealWidth: 340)

                    ActionPreviewView(
                        selectedID: state.selectedActionID,
                        actions: state.actions
                    )
                    .frame(minWidth: 240, idealWidth: 340)
                }
            }
        }
        .frame(width: 680, height: 460)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onKeyPress(.downArrow) { state.selectNext(); return .handled }
        .onKeyPress(.upArrow) { state.selectPrevious(); return .handled }
        .onKeyPress(.return) {
            return .handled
        }
    }
}
