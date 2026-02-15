import Combine
import SwiftUI

struct PickerView: View {
    @Bindable var state: PickerState
    let panelController: PanelController
    @Environment(\.vibeTheme) private var theme

    private var coordinator: PickerCoordinator? {
        panelController.coordinator
    }

    private var searchBinding: Binding<String> {
        switch state.mode {
        case .search, .pushedActions:
            $state.query
        case .parameterInput:
            $state.parameterQuery
        case .result:
            .constant("")
        }
    }

    private var searchPlaceholder: String {
        switch state.mode {
        case .search:
            "Search actions..."
        case .parameterInput:
            state.currentParameter?.label ?? "Enter value..."
        case .pushedActions:
            "Filter..."
        case .result:
            ""
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if case .result = state.mode {
                // No search field in result mode
            } else {
                PickerSearchField(text: searchBinding, placeholder: searchPlaceholder)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .id(state.mode)
            }

            if state.mode != .search {
                BreadcrumbView(state: state) {
                    _ = state.popMode()
                }
            }

            Divider()

            content
        }
        .frame(width: 680, height: 460)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                if let tint = theme.backgroundTint {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(tint)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            if let glow = theme.borderGlow {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(glow, lineWidth: 1)
            }
        }
        .accessibilityIdentifier("pickerView")
        .onKeyPress(.downArrow) { state.selectNext(); return .handled }
        .onKeyPress(.upArrow) { state.selectPrevious(); return .handled }
        .onKeyPress(.return) {
            coordinator?.handleReturn()
            return .handled
        }
        .onKeyPress(.tab) {
            coordinator?.handleTab()
            return .handled
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.mode {
        case .search, .pushedActions:
            actionListContent
        case .parameterInput:
            parameterContent
        case let .result(title, body):
            ResultView(title: title, message: body)
        }
    }

    @ViewBuilder
    private var actionListContent: some View {
        if state.isLoading, state.actions.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("pickerLoading")
        } else if state.actions.isEmpty, !state.query.isEmpty {
            ContentUnavailableView.search(text: state.query)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("pickerNoResults")
        } else {
            HSplitView {
                ActionListView(
                    actions: state.actions,
                    selectedID: $state.selectedActionID,
                    actionCache: state.actionCache
                )
                .frame(minWidth: 280, idealWidth: 340)

                ActionPreviewView(
                    selectedID: state.selectedActionID,
                    actions: state.actions,
                    actionCache: state.actionCache
                )
                .frame(minWidth: 240, idealWidth: 340)
            }
        }
    }

    @ViewBuilder
    private var parameterContent: some View {
        HSplitView {
            ParameterInputView(state: state)
                .frame(minWidth: 280, idealWidth: 340)

            ParameterPreviewView(state: state)
                .frame(minWidth: 240, idealWidth: 340)
        }
    }
}
