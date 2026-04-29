import SwiftUI

struct ActionListView: View {
    let actions: [ActionItem]
    @Binding var selectedID: ActionID?
    var actionCache: [ActionID: any Action] = [:]
    var activationCounters: [ActionID: Int] = [:]
    var rowHeight: CGFloat = 52
    var onActivate: ((ActionID) -> Void)?
    @Environment(\.vibeTheme) private var theme

    private static let selectionInset: CGFloat = 8
    private static let rowContentInset: CGFloat = 12
    private static let selectionCornerRadius: CGFloat = 8

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
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(actions) { item in
                        row(for: item, hotkeyNumber: hotkeys[item.id])
                            .id(item.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollContentBackground(.hidden)
            .subtleScrollers()
            .accessibilityIdentifier("actionList")
            .onChange(of: selectedID) { _, newID in
                if let newID {
                    proxy.scrollTo(newID, anchor: nil)
                }
            }
        }
    }

    @ViewBuilder
    private func row(for item: ActionItem, hotkeyNumber: Int?) -> some View {
        let isSelected = selectedID == item.id
        let singleClick = actionCache[item.id]?.activatesOnSingleClick ?? false
        let trigger = activationCounters[item.id] ?? 0

        actionRow(for: item, hotkeyNumber: hotkeyNumber, isSelected: isSelected)
            .padding(.horizontal, Self.rowContentInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: rowHeight)
            .background(
                RoundedRectangle(cornerRadius: Self.selectionCornerRadius, style: .continuous)
                    .fill(isSelected ? theme.accent : Color.clear)
            )
            .padding(.horizontal, Self.selectionInset)
            .activationPulse(trigger: trigger, cornerRadius: Self.selectionCornerRadius, inset: Self.selectionInset)
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

    @ViewBuilder
    private func actionRow(for item: ActionItem, hotkeyNumber: Int?, isSelected: Bool) -> some View {
        if let action = actionCache[item.id],
           let customView = action.makeListItemView() {
            customView
                .environment(\.isPickerRowSelected, isSelected)
        } else {
            ActionListItemView(
                item: item,
                hotkeyNumber: hotkeyNumber,
                rowHeight: rowHeight,
                isSelected: isSelected
            )
        }
    }
}

// MARK: - Activation pulse

private struct ActivationPulseValues: Equatable {
    var scale: CGFloat = 1.0
    var glow: CGFloat = 0.0
}

private struct ActivationPulseModifier: ViewModifier {
    let trigger: Int
    let cornerRadius: CGFloat
    let inset: CGFloat

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(
                initialValue: ActivationPulseValues(),
                trigger: trigger
            ) { view, value in
                view
                    .scaleEffect(value.scale)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.white.opacity(0.45 * value.glow))
                            .blendMode(.plusLighter)
                            .padding(.horizontal, inset)
                            .allowsHitTesting(false)
                    )
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    SpringKeyframe(0.94, duration: 0.08, spring: .snappy)
                    SpringKeyframe(1.05, duration: 0.18, spring: .bouncy)
                    SpringKeyframe(1.0, duration: 0.18, spring: .smooth)
                }
                KeyframeTrack(\.glow) {
                    LinearKeyframe(1.0, duration: 0.06)
                    LinearKeyframe(0.7, duration: 0.12)
                    LinearKeyframe(0.0, duration: 0.22)
                }
            }
    }
}

private extension View {
    func activationPulse(trigger: Int, cornerRadius: CGFloat, inset: CGFloat) -> some View {
        modifier(ActivationPulseModifier(trigger: trigger, cornerRadius: cornerRadius, inset: inset))
    }
}

private struct IsPickerRowSelectedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isPickerRowSelected: Bool {
        get { self[IsPickerRowSelectedKey.self] }
        set { self[IsPickerRowSelectedKey.self] = newValue }
    }
}
