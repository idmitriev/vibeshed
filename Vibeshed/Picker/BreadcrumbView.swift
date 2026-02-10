import SwiftUI

struct BreadcrumbView: View {
    let state: PickerState
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            breadcrumbText
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial.opacity(0.5))
    }

    @ViewBuilder
    private var breadcrumbText: some View {
        switch state.mode {
        case .search:
            EmptyView()

        case .parameterInput:
            if let action = state.activeAction, let param = state.currentParameter {
                HStack(spacing: 4) {
                    Text(action.title)
                        .fontWeight(.medium)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                    Text(param.label)
                }
            }

        case .pushedActions:
            if let action = state.activeAction {
                HStack(spacing: 4) {
                    Text(action.title)
                        .fontWeight(.medium)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                    Text("Choose...")
                }
            } else {
                Text("Choose...")
            }

        case let .result(title, _):
            HStack(spacing: 4) {
                if let action = state.activeAction {
                    Text(action.title)
                        .fontWeight(.medium)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                }
                Text(title)
            }
        }
    }
}
