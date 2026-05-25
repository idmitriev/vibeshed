import SwiftUI

struct LayoutCorrectionBanner: View {
    let hint: LayoutCorrectionHint
    @Environment(\.vibeTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "keyboard")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(hint.correctedQuery)
                .font(.caption)
                .fontWeight(.medium)
                .fontDesign(.monospaced)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(theme.selectionHighlight))
        .transition(.opacity)
    }
}
