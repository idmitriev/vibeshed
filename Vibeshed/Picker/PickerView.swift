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

    private var searchFieldPills: [SearchFieldPill] {
        switch state.mode {
        case .search:
            []
        case .parameterInput:
            if let action = state.activeAction {
                [SearchFieldPill(
                    id: action.id.rawValue,
                    title: action.title,
                    iconSystemName: action.iconName,
                    detail: state.currentParameter?.label
                )]
            } else {
                []
            }
        case .pushedActions:
            if let action = state.activeAction {
                [SearchFieldPill(
                    id: action.id.rawValue,
                    title: action.title,
                    iconSystemName: action.iconName,
                    detail: nil
                )]
            } else {
                []
            }
        case .result:
            []
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if case .result = state.mode {
                BreadcrumbView(state: state) {
                    _ = state.popMode()
                }
            } else {
                PickerSearchField(
                    text: searchBinding,
                    placeholder: searchPlaceholder,
                    pills: searchFieldPills,
                    onRemovePill: { _ in _ = state.popMode() },
                    onBackspaceEmpty: { _ = state.popMode() }
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .id(state.mode)
            }

            if let hint = state.layoutCorrectionHint, case .search = state.mode {
                LayoutCorrectionBanner(hint: hint)
            }

            Divider()

            content
        }
        .frame(width: 760, height: 520)
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
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .shadow(
            color: theme.shadowColor ?? .black.opacity(0.35),
            radius: 8,
            y: 2
        )
        .padding(16)
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
        .onKeyPress(characters: .init(charactersIn: "123456789"), phases: .down) { keyPress in
            guard keyPress.modifiers == .command,
                  let digit = keyPress.characters.first?.wholeNumberValue
            else { return .ignored }
            coordinator?.handleCmdNumber(digit)
            return .handled
        }
        .onKeyPress(.pageDown) { state.selectNextPage(); return .handled }
        .onKeyPress(.pageUp) { state.selectPreviousPage(); return .handled }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch state.mode {
            case .search, .pushedActions:
                actionListContent
                    .transition(.opacity)
            case .parameterInput:
                parameterContent
                    .transition(.opacity)
            case let .result(title, body):
                ResultView(title: title, message: body)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.mode)
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
                    actionIndex: Dictionary(uniqueKeysWithValues: state.actions.map { ($0.id, $0) }),
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
