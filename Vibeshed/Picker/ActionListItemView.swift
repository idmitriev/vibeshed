import SwiftUI

struct ActionListItemView: View, Equatable {
    let item: ActionItem
    var hotkeyNumber: Int?
    var rowHeight: CGFloat = 52
    var isSelected: Bool = false
    @Environment(\.vibeTheme) private var theme

    static func == (lhs: ActionListItemView, rhs: ActionListItemView) -> Bool {
        lhs.item == rhs.item
            && lhs.hotkeyNumber == rhs.hotkeyNumber
            && lhs.rowHeight == rhs.rowHeight
            && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.iconSystemName ?? "sparkle")
                .font(.title3)
                .frame(width: 32, height: 32)
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: 2) {
                highlightedTitle
                    .font(.body)
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)

                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                }
            }

            Spacer()

            if item.hasParameters {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
            }

            if let number = hotkeyNumber {
                Text("\u{2318}\(number)")
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
                    .monospacedDigit()
            }
        }
        .frame(height: rowHeight)
        .contentShape(Rectangle())
    }

    private var iconColor: Color {
        isSelected ? .white : .primary.opacity(0.65)
    }

    private var primaryTextColor: Color {
        isSelected ? .white : .primary
    }

    private var secondaryTextColor: Color {
        isSelected ? Color.white.opacity(0.85) : .secondary
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
            attributed[attrRange].foregroundColor = isSelected ? .white : theme.searchHighlight
            attributed[attrRange].underlineStyle = .single
        }
        return attributed
    }
}
