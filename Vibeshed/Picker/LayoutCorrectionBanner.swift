import SwiftUI

struct LayoutCorrectionBanner: View {
    let hint: LayoutCorrectionHint
    @Environment(\.vibeTheme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "keyboard")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Showing results for: ")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(hint.correctedQuery)
                .font(.callout)
                .fontWeight(.medium)
                .fontDesign(.monospaced)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(theme.selectionHighlight)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
