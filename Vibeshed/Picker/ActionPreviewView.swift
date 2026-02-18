import SwiftUI

struct ActionPreviewView: View {
    let selectedID: ActionID?
    let actions: [ActionItem]
    var actionCache: [ActionID: any Action] = [:]

    private var selectedItem: ActionItem? {
        guard let id = selectedID else { return nil }
        return actions.first { $0.id == id }
    }

    var body: some View {
        Group {
            if let item = selectedItem {
                if let action = actionCache[item.id],
                   let customPreview = action.makePreviewView() {
                    customPreview
                } else {
                    defaultPreview(for: item)
                }
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "sparkle",
                    description: Text("Select an action to see details")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("actionPreview")
    }

    @ViewBuilder
    private func defaultPreview(for item: ActionItem) -> some View {
        VStack(spacing: 12) {
            Image(systemName: item.iconSystemName ?? "sparkle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text(item.title)
                .font(.title2)
                .fontWeight(.medium)

            Text(item.subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Text("Module: \(item.moduleID)")
                .font(.caption)
                .foregroundStyle(.tertiary)

            if let action = actionCache[item.id], !action.parameters.isEmpty {
                Divider()
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Parameters")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)

                    ForEach(action.parameters) { param in
                        HStack(spacing: 6) {
                            Image(systemName: parameterIcon(for: param.type))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(param.label)
                                .font(.caption)
                            if param.isRequired {
                                Text("required")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding()
    }

    private func parameterIcon(for type: ParameterType) -> String {
        switch type {
        case .text: "character.cursor.ibeam"
        case .number: "number"
        case .toggle: "switch.2"
        case .selection: "list.bullet"
        case .dynamicSelection: "magnifyingglass"
        case .path: "folder"
        }
    }
}
