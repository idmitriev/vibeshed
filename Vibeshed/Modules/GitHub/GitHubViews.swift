import SwiftUI

struct GitHubActionListItemView: View {
    let action: GitHubAction

    var body: some View {
        HStack(spacing: 10) {
            avatarOrIcon
                .frame(width: 28, height: 28)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.body)
                    .lineLimit(1)

                if !action.subtitle.isEmpty {
                    Text(action.subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 4) {
                if let stateIcon = action.stateIcon,
                   let stateColor = action.stateColor {
                    Image(systemName: stateIcon)
                        .font(.caption)
                        .foregroundStyle(stateColor)
                }
                if let itemType = action.githubItemType {
                    Text(itemType.rawValue.uppercased())
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var avatarOrIcon: some View {
        if let avatarURL = action.avatarURL,
           let url = URL(string: avatarURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    fallbackIcon
                }
            }
        } else {
            fallbackIcon
        }
    }

    private var fallbackIcon: some View {
        Image(
            systemName: action.iconName
                ?? "chevron.left.forwardslash.chevron.right"
        )
        .font(.title3)
        .foregroundStyle(.secondary)
    }
}

struct GitHubActionPreviewView: View {
    let action: GitHubAction

    var body: some View {
        PreviewLayout(moduleName: "github") {
            PreviewHeader(title: action.title, subtitle: action.subtitle) {
                avatarHero
            }

            badgeRow

            if let desc = action.itemDescription, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

            labelsRow

            metadataSection
        }
    }

    @ViewBuilder
    private var avatarHero: some View {
        if let avatarURL = action.avatarURL,
           let url = URL(string: avatarURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    previewFallbackIcon
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(action.githubItemType == .repo
                ? AnyShape(RoundedRectangle(cornerRadius: 10))
                : AnyShape(Circle()))
        } else {
            previewFallbackIcon
        }
    }

    private var previewFallbackIcon: some View {
        Image(
            systemName: action.iconName
                ?? "chevron.left.forwardslash.chevron.right"
        )
        .font(.system(size: 48))
        .foregroundStyle(.secondary)
        .frame(width: 64, height: 64)
    }

    @ViewBuilder
    private var badgeRow: some View {
        HStack(spacing: 8) {
            if let stateIcon = action.stateIcon,
               let stateColor = action.stateColor {
                PreviewPill(
                    text: stateLabel,
                    icon: stateIcon,
                    color: stateColor
                )
            }
            if let itemType = action.githubItemType {
                PreviewPill(
                    text: typeLabel(for: itemType),
                    icon: iconForType(itemType),
                    color: .secondary
                )
            }
        }
    }

    @ViewBuilder
    private var labelsRow: some View {
        if let labels = action.labels, !labels.isEmpty {
            GitHubFlowLayout(spacing: 4) {
                ForEach(labels, id: \.self) { label in
                    Text(label)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let stars = action.repoStars {
                PreviewMetadataRow(
                    icon: "star",
                    label: "Stars",
                    value: formatCount(stars)
                )
            }
            if let lang = action.repoLanguage {
                PreviewMetadataRow(
                    icon: "chevron.left.forwardslash.chevron.right",
                    label: "Language",
                    value: lang
                )
            }
            if let created = action.createdAt {
                PreviewMetadataRow(
                    icon: "calendar",
                    label: "Created",
                    value: formatDate(created)
                )
            }
            if let htmlURL = action.htmlURL {
                Text(htmlURL)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
        }
    }

    private var stateLabel: String {
        if let icon = action.stateIcon {
            switch icon {
            case "circle.fill": return "Open"
            case "checkmark.circle.fill": return "Closed"
            case "arrow.triangle.pull": return "Open"
            case "arrow.triangle.merge": return "Merged"
            case "xmark.circle.fill": return "Closed"
            case "doc": return "Draft"
            default: return ""
            }
        }
        return ""
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000.0)
        }
        return "\(count)"
    }

    private func formatDate(_ isoDate: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: isoDate) {
            let display = DateFormatter()
            display.dateStyle = .medium
            return display.string(from: date)
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: isoDate) {
            let display = DateFormatter()
            display.dateStyle = .medium
            return display.string(from: date)
        }
        return isoDate
    }
}

// MARK: - Flow Layout

private struct GitHubFlowLayout: Layout {
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

private func iconForType(_ type: GitHubItemType) -> String {
    switch type {
    case .repo: "folder"
    case .issue: "exclamationmark.circle"
    case .pr: "arrow.triangle.pull"
    case .notification: "bell"
    }
}

private func typeLabel(for type: GitHubItemType) -> String {
    switch type {
    case .repo: "Repository"
    case .issue: "Issue"
    case .pr: "Pull Request"
    case .notification: "Notification"
    }
}
