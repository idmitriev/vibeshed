import AppKit
import SwiftUI

struct ParameterInputView: View {
    @Bindable var state: PickerState
    var onConfirm: (() -> Void)?
    @Environment(\.vibeTheme) private var theme

    var body: some View {
        Group {
            if let param = state.currentParameter {
                parameterContent(for: param)
            } else {
                ContentUnavailableView(
                    "No Parameter",
                    systemImage: "questionmark.circle",
                    description: Text("No parameter to configure")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func parameterContent(for param: ActionParameter) -> some View {
        switch param.type {
        case .selection, .dynamicSelection:
            selectionList(for: param)
        case .toggle:
            selectionList(for: param)
        case .text, .number, .path:
            // These types use the search field directly for input.
            // Show a hint in the list area.
            textInputHint(for: param)
        }
    }

    @ViewBuilder
    private func selectionList(for param: ActionParameter) -> some View {
        if state.isLoadingOptions, state.parameterOptions.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if state.parameterOptions.isEmpty {
            ContentUnavailableView(
                "No Options",
                systemImage: "tray",
                description: Text("No options available for \(param.label)")
            )
        } else {
            ScrollViewReader { proxy in
                let hotkeys: [String: Int] = {
                    var map = [String: Int]()
                    for i in 0 ..< min(state.parameterOptions.count, 9) {
                        map[state.parameterOptions[i].id] = i + 1
                    }
                    return map
                }()
                List(selection: $state.selectedParameterOptionID) {
                    ForEach(state.parameterOptions) { option in
                        ParameterOptionRow(
                            option: option,
                            hotkeyNumber: hotkeys[option.id]
                        )
                        .tag(option.id)
                        .listRowSeparator(.hidden)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            state.selectedParameterOptionID = option.id
                            onConfirm?()
                        }
                        .onTapGesture(count: 1) {
                            state.selectedParameterOptionID = option.id
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .subtleScrollers()
                .tint(theme.accent)
                .accessibilityIdentifier("parameterOptionList")
                .onChange(of: state.selectedParameterOptionID) { _, newID in
                    if let newID {
                        proxy.scrollTo(newID, anchor: nil)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func textInputHint(for param: ActionParameter) -> some View {
        VStack(spacing: 16) {
            Image(systemName: iconForParameterType(param.type))
                .font(.largeTitle)
                .foregroundStyle(.primary.opacity(0.5))

            Text("Type a value and press Return")
                .font(.body)
                .foregroundStyle(.primary.opacity(0.7))

            if case let .number(min, max) = param.type {
                if let min, let max {
                    Text("Range: \(min, specifier: "%.0f") – \(max, specifier: "%.0f")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let min {
                    Text("Minimum: \(min, specifier: "%.0f")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let max {
                    Text("Maximum: \(max, specifier: "%.0f")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if case let .path(allowsDirectories) = param.type {
                Button("Browse...") {
                    browseForPath(allowsDirectories: allowsDirectories)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func iconForParameterType(_ type: ParameterType) -> String {
        switch type {
        case .text: "character.cursor.ibeam"
        case .number: "number"
        case .path: "folder"
        case .toggle: "switch.2"
        case .selection: "list.bullet"
        case .dynamicSelection: "list.bullet"
        }
    }

    private func browseForPath(allowsDirectories: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !allowsDirectories
        panel.canChooseDirectories = allowsDirectories
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                MainActor.assumeIsolated {
                    state.parameterQuery = url.path
                }
            }
        }
    }
}

struct ParameterOptionRow: View, Equatable {
    let option: ParameterOption
    var hotkeyNumber: Int?
    @Environment(\.vibeTheme) private var theme

    static func == (lhs: ParameterOptionRow, rhs: ParameterOptionRow) -> Bool {
        lhs.option == rhs.option && lhs.hotkeyNumber == rhs.hotkeyNumber
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let iconURL = option.iconURL {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: iconURL.path))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: option.iconName ?? "sparkle")
                        .font(.title3)
                        .foregroundStyle(.primary.opacity(0.65))
                }
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                highlightedLabel
                    .font(.body)
                    .lineLimit(1)

                if let subtitle = option.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let number = hotkeyNumber {
                Text("\u{2318}\(number)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var highlightedLabel: some View {
        if let ranges = option.labelHighlightRanges, !ranges.isEmpty {
            Text(highlightedAttributedString(option.label, ranges: ranges))
        } else {
            Text(option.label)
        }
    }

    private func highlightedAttributedString(
        _ string: String,
        ranges: [Range<String.Index>]
    ) -> AttributedString {
        var attributed = AttributedString(string)
        for range in ranges {
            guard let attrRange = Range(range, in: attributed) else { continue }
            attributed[attrRange].foregroundColor = theme.searchHighlight
            attributed[attrRange].underlineStyle = .single
        }
        return attributed
    }
}
