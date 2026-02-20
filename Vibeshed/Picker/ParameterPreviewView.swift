import SwiftUI

struct ParameterPreviewView: View {
    let state: PickerState
    @Environment(\.vibeTheme) private var theme

    private var action: (any Action)? {
        state.activeAction
    }

    var body: some View {
        Group {
            if let action {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Action header
                        Image(systemName: action.iconName ?? "sparkle")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)

                        Text(action.title)
                            .font(.title3)
                            .fontWeight(.medium)
                            .lineLimit(2)

                        Text(action.subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)

                        Divider()

                        // Parameter progress
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Parameters")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .textCase(.uppercase)

                            ForEach(action.parameters) { param in
                                parameterRow(param)
                            }
                        }

                        Spacer(minLength: 8)
                    }
                    .padding()
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
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                    }
                }

                if isFilled, let value = state.collectedValues[param.id] {
                    Text(displayValue(value, for: param))
                        .font(.caption)
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
