import SwiftUI

struct ActionPreviewView: View {
    let selectedID: ActionID?
    let actions: [ActionItem]

    private var selectedItem: ActionItem? {
        guard let id = selectedID else { return nil }
        return actions.first { $0.id == id }
    }

    var body: some View {
        Group {
            if let item = selectedItem {
                VStack(spacing: 12) {
                    Image(systemName: item.iconSystemName ?? "sparkle")
                        .font(.largeTitle)
                    Text(item.title)
                        .font(.title2)
                    Text(item.subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text("Module: \(item.moduleID)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
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
}
