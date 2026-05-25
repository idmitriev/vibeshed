import Combine
import SwiftUI

struct PickerView: View {
    @Bindable var state: PickerState
    let panelController: PanelController
    var appearance: AppConfig.AppearanceConfig = .init()
    @Environment(\.vibeTheme) private var theme

    @State private var previewVisible = false
    @State private var previewIdleTask: Task<Void, Never>?

    private static let previewIdleDelay: Duration = .milliseconds(1200)
    private let glassInset: CGFloat = 6
    private let glassCornerRadius: CGFloat = 10

    private var searchBarTotalHeight: CGFloat {
        appearance.searchBarHeight + glassInset
    }

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
        ZStack(alignment: .top) {
            content

            // Glass preview panel — floats on the trailing edge over results
            if previewVisible, showsPreview {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    previewPanel
                        .frame(width: 340)
                        .frame(maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: glassCornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: glassCornerRadius, style: .continuous)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 0.5)
                        )
                        .padding(.trailing, glassInset)
                        .padding(.top, searchBarTotalHeight + glassInset)
                        .padding(.bottom, glassInset)
                        .transition(previewTransition)
                }
            }

            // Glass search bar accessory — floats above scrolling content
            Group {
                if case .result = state.mode {
                    BreadcrumbView(state: state) {
                        _ = state.popMode()
                    }
                    .frame(height: appearance.searchBarHeight)
                } else {
                    HStack(spacing: 0) {
                        PickerSearchField(
                            text: searchBinding,
                            placeholder: searchPlaceholder,
                            pills: searchFieldPills,
                            onRemovePill: { _ in _ = state.popMode() },
                            onBackspaceEmpty: { _ = state.popMode() }
                        )

                        if let hint = state.layoutCorrectionHint, case .search = state.mode {
                            LayoutCorrectionBanner(hint: hint)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: appearance.searchBarHeight)
                    .id(state.mode)
                }
            }
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: glassCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: glassCornerRadius, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 0.5)
            )
            .padding(.horizontal, glassInset)
            .padding(.top, glassInset)
        }
        .frame(width: appearance.panelWidth, height: appearance.panelHeight)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: appearance.cornerRadius)
                    .fill(.ultraThinMaterial)
                if let tint = theme.backgroundTint {
                    RoundedRectangle(cornerRadius: appearance.cornerRadius)
                        .fill(tint)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: appearance.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: appearance.cornerRadius)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
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
        .onAppear { schedulePreviewReveal() }
        .onDisappear {
            previewIdleTask?.cancel()
            previewVisible = false
        }
        .onChange(of: state.query) { _, _ in schedulePreviewReveal() }
        .onChange(of: state.parameterQuery) { _, _ in schedulePreviewReveal() }
        .onChange(of: state.selectedActionID) { _, _ in schedulePreviewReveal() }
        .onChange(of: state.selectedParameterOptionID) { _, _ in schedulePreviewReveal() }
        .onChange(of: state.mode) { _, _ in schedulePreviewReveal() }
    }

    private func schedulePreviewReveal() {
        previewIdleTask?.cancel()
        if previewVisible {
            withAnimation(.easeOut(duration: 0.18)) {
                previewVisible = false
            }
        }
        previewIdleTask = Task { @MainActor in
            try? await Task.sleep(for: Self.previewIdleDelay)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                previewVisible = true
            }
        }
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
                    .padding(.top, searchBarTotalHeight)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.mode)
    }

    @ViewBuilder
    private var actionListContent: some View {
        if state.isLoading, state.actions.isEmpty {
            ProgressView()
                .padding(.top, searchBarTotalHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("pickerLoading")
        } else if state.actions.isEmpty, !state.query.isEmpty {
            ContentUnavailableView.search(text: state.query)
                .padding(.top, searchBarTotalHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("pickerNoResults")
        } else {
            ActionListView(
                actions: state.actions,
                selectedID: $state.selectedActionID,
                actionCache: state.actionCache,
                activationCounters: state.activationCounters,
                rowHeight: appearance.rowHeight,
                topInset: searchBarTotalHeight,
                onActivate: { id in coordinator?.activateAction(id: id) }
            )
        }
    }

    @ViewBuilder
    private var parameterContent: some View {
        ParameterInputView(
            state: state,
            rowHeight: appearance.rowHeight,
            topInset: searchBarTotalHeight,
            onConfirm: { coordinator?.handleReturn() }
        )
    }

    private var showsPreview: Bool {
        switch state.mode {
        case .search, .pushedActions, .parameterInput:
            true
        case .result:
            false
        }
    }

    @ViewBuilder
    private var previewPanel: some View {
        switch state.mode {
        case .search, .pushedActions:
            ActionPreviewView(
                selectedID: state.selectedActionID,
                actionIndex: Dictionary(uniqueKeysWithValues: state.actions.map { ($0.id, $0) }),
                actionCache: state.actionCache
            )
        case .parameterInput:
            ParameterPreviewView(state: state)
        case .result:
            EmptyView()
        }
    }

    private var previewTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.96, anchor: .trailing)),
            removal: .move(edge: .trailing)
                .combined(with: .opacity)
        )
    }
}
