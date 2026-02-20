import AppKit
import SwiftUI

struct ParameterInputView: View {
    @Bindable var state: PickerState

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
                List(state.parameterOptions, selection: $state.selectedParameterOptionID) { option in
                    ParameterOptionRow(option: option)
                        .tag(option.id)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
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
                .foregroundStyle(.secondary)

            Text("Type a value and press Return")
                .font(.body)
                .foregroundStyle(.secondary)

            if case let .number(min, max) = param.type {
                if let min, let max {
                    Text("Range: \(min, specifier: "%.0f") – \(max, specifier: "%.0f")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if let min {
                    Text("Minimum: \(min, specifier: "%.0f")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if let max {
                    Text("Maximum: \(max, specifier: "%.0f")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
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

struct ParameterOptionRow: View {
    let option: ParameterOption

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let iconURL = option.iconURL {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: iconURL.path))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if let iconName = option.iconName {
                    Image(systemName: iconName)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 28, height: 28)

            Text(option.label)
                .font(.body)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
