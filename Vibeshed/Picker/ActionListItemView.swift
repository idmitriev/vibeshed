import SwiftUI

struct ActionListItemView: View, Equatable {
    let item: ActionItem
    var hotkeyNumber: Int?
    @Environment(\.vibeTheme) private var theme

    static func == (lhs: ActionListItemView, rhs: ActionListItemView) -> Bool {
        lhs.item == rhs.item && lhs.hotkeyNumber == rhs.hotkeyNumber
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.iconSystemName ?? "sparkle")
                .font(.title3)
                .frame(width: 32, height: 32)
                .foregroundStyle(.primary.opacity(0.65))

            VStack(alignment: .leading, spacing: 2) {
                highlightedTitle
                    .font(.body)
                    .lineLimit(1)

                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if item.hasParameters {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let number = hotkeyNumber {
                Text("\u{2318}\(number)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var highlightedTitle: some View {
        if let ranges = item.titleHighlightRanges, !ranges.isEmpty {
            Text(highlightedAttributedString(item.title, ranges: ranges))
        } else {
            Text(item.title)
        }
    }

    private func highlightedAttributedString(
        _ string: String,
        ranges: [Range<String.Index>]
    ) -> AttributedString {
        var attributed = AttributedString(string)
        for range in ranges {
            guard let attrRange = Range(range, in: attributed) else { continue }
            attributed[attrRange].foregroundColor = theme.searchHighlight
            attributed[attrRange].underlineStyle = .single
        }
        return attributed
    }
}
