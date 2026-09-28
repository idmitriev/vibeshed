import SwiftUI

// MARK: - Preview Header

struct PreviewHeader<Hero: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let hero: () -> Hero

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            hero()

            Text(title)
                .font(.title3)
                .fontWeight(.medium)
                .lineLimit(3)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
    }
}

extension PreviewHeader where Hero == AnyView {
    init(
        title: String,
        subtitle: String,
        systemIcon: String,
        iconColor: Color = Color.primary.opacity(0.5)
    ) {
        self.title = title
        self.subtitle = subtitle
        self.hero = {
            AnyView(
                Image(systemName: systemIcon)
                    .font(.system(size: 56))
                    .foregroundStyle(iconColor)
                    .frame(width: 72, height: 72)
            )
        }
    }
}

// MARK: - Preview Metadata Row

struct PreviewMetadataRow: View {
    let icon: String
    let label: String
    let value: String
    var valueColor: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .foregroundStyle(valueColor)
                .lineLimit(2)
        }
    }
}

// MARK: - Preview Module Badge

struct PreviewModuleBadge: View {
    let moduleName: String

    var body: some View {
        Text("Module: \(moduleName)")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }
}

// MARK: - Preview Layout

struct PreviewLayout<Content: View>: View {
    let moduleName: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content()

            Spacer(minLength: 0)

            PreviewModuleBadge(moduleName: moduleName)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
    }
}

// MARK: - Preview Flow Layout

/// Lays views out in rows, wrapping to the next row when one runs out of width.
struct PreviewFlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() where index < subviews.count {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalHeight = y + rowHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

// MARK: - Preview Pill Badge

struct PreviewPill: View {
    let text: String
    var icon: String?
    var color: Color = .accentColor

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption)
            }
            Text(text)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.2))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }
}
