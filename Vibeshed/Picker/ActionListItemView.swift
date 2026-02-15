import SwiftUI

struct ActionListItemView: View {
    let item: ActionItem
    @Environment(\.vibeTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.iconSystemName ?? "sparkle")
                .font(.title3)
                .frame(width: 28, height: 28)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                highlightedTitle
                    .font(.body)
                    .lineLimit(1)

                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if item.hasParameters {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.vertical, 4)
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
            attributed[attrRange].font = .body.bold()
        }
        return attributed
    }
}
