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
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder
    private var breadcrumbText: some View {
        if case let .result(title, _) = state.mode {
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
