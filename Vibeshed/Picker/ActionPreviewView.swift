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
        PreviewLayout(moduleName: item.moduleID) {
            PreviewHeader(title: item.title, subtitle: item.subtitle) {
                Image(systemName: item.iconSystemName ?? "sparkle")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                    .frame(width: 64, height: 64)
            }

            if let action = actionCache[item.id], !action.parameters.isEmpty {
                Divider()

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
            }
        }
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
