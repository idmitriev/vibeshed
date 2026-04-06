import AppKit
import SwiftUI

struct ParameterPreviewView: View {
    let state: PickerState
    @Environment(\.vibeTheme) private var theme

    private var action: (any Action)? {
        state.activeAction
    }

    private var selectedOption: ParameterOption? {
        guard let selectedID = state.selectedParameterOptionID else { return nil }
        return state.parameterOptions.first { $0.id == selectedID }
    }

    private var moduleName: String {
        action?.id.moduleID ?? "unknown"
    }

    var body: some View {
        Group {
            if let action {
                PreviewLayout(moduleName: moduleName) {
                    PreviewHeader(
                        title: selectedOption?.label ?? action.title,
                        subtitle: selectedOption?.subtitle ?? action.subtitle
                    ) {
                        Group {
                            if let iconURL = selectedOption?.iconURL {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: iconURL.path))
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            } else {
                                Image(systemName: action.iconName ?? "sparkle")
                                    .font(.system(size: 56))
                                    .foregroundStyle(.primary.opacity(0.5))
                            }
                        }
                        .frame(width: 72, height: 72)
                    }

                    Divider()

                    // Parameter progress
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Parameters")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        ForEach(action.parameters) { param in
                            parameterRow(param)
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Action",
                    systemImage: "sparkle",
                    description: Text("Select an action to configure")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func parameterRow(_ param: ActionParameter) -> some View {
        let isCurrent = state.currentParameter?.id == param.id
        let isFilled = state.collectedValues[param.id] != nil

        HStack(spacing: 8) {
            Image(systemName: isFilled ? "checkmark.circle.fill" : (isCurrent ? "circle.dotted" : "circle"))
                .foregroundColor(isFilled ? .green : (isCurrent ? theme.accent : .gray))
                .font(.body)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(param.label)
                        .font(.body)
                        .fontWeight(isCurrent ? .medium : .regular)

                    if !param.isRequired {
                        Text("optional")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.tertiary.opacity(0.5), in: RoundedRectangle(cornerRadius: 3))
                    }
                }

                if isFilled, let value = state.collectedValues[param.id] {
                    Text(displayValue(value, for: param))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
        .background(isCurrent ? theme.selectionHighlight : .clear, in: RoundedRectangle(cornerRadius: 6))
    }

    private func displayValue(_ value: Any, for param: ActionParameter) -> String {
        if let stringValue = value as? String {
            // For selections, try to find the label
            if case let .selection(options) = param.type,
               let option = options.first(where: { $0.id == stringValue }) {
                return option.label
            }
            // For dynamic selections, look in current options
            if case .dynamicSelection = param.type,
               let option = state.parameterOptions.first(where: { $0.id == stringValue }) {
                return option.label
            }
            if stringValue == "true" { return "On" }
            if stringValue == "false" { return "Off" }
            return stringValue
        }
        return String(describing: value)
    }
}
