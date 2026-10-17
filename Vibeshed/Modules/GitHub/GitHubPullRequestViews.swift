import SwiftUI

/// The preview of an open pull request from the main search: where it is, whose it is,
/// and whether it's ready (draft, review, checks). Listed without a token, it knows
/// less, and leaves out what it doesn't know.
struct GitHubPullRequestPreviewView: View {
    let action: GitHubAction
    let pullRequest: GitHubPullRequest

    var body: some View {
        PreviewLayout(moduleName: "github") {
            PreviewHeader(title: pullRequest.title, subtitle: "\(pullRequest.repository) #\(pullRequest.number)") {
                GitHubAvatarHero(action: action)
            }

            PreviewFlowLayout(spacing: 6) {
                stateBadge
                if pullRequest.matchedFilters.contains(.reviewRequested) {
                    PreviewPill(text: "Your review requested", icon: "eye", color: .orange)
                }
                reviewBadge
                checksBadge
            }

            metadataRows
        }
    }

    private var stateBadge: some View {
        pullRequest.isDraft
            ? PreviewPill(text: "Draft", icon: "doc", color: .gray)
            : PreviewPill(text: "Open", icon: "arrow.triangle.pull", color: .green)
    }

    @ViewBuilder
    private var reviewBadge: some View {
        switch pullRequest.reviewDecision {
        case .approved:
            PreviewPill(text: "Approved", icon: "checkmark.seal", color: .green)
        case .changesRequested:
            PreviewPill(text: "Changes requested", icon: "exclamationmark.bubble", color: .red)
        case .reviewRequired:
            PreviewPill(text: "Review required", icon: "person.badge.clock", color: .orange)
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private var checksBadge: some View {
        switch pullRequest.checks {
        case .passing:
            PreviewPill(text: "Checks passing", icon: "checkmark.circle.fill", color: .green)
        case .failing:
            PreviewPill(text: "Checks failing", icon: "xmark.circle.fill", color: .red)
        case .running:
            PreviewPill(text: "Checks running", icon: "clock", color: .yellow)
        case nil:
            EmptyView()
        }
    }

    private var metadataRows: some View {
        VStack(alignment: .leading, spacing: 4) {
            PreviewMetadataRow(icon: "folder", label: "Repository", value: pullRequest.repository)
            PreviewMetadataRow(icon: "person", label: "Author", value: pullRequest.author)
            if let head = pullRequest.headBranch {
                PreviewMetadataRow(
                    icon: "arrow.triangle.branch",
                    label: "Branch",
                    value: pullRequest.baseBranch.map { "\(head) → \($0)" } ?? head
                )
            }
            if let updated = pullRequest.updatedAt {
                PreviewMetadataRow(icon: "clock", label: "Updated", value: relativeTime(updated))
            }
            if let changes {
                PreviewMetadataRow(icon: "plusminus", label: "Changes", value: changes)
            }
            if !pullRequest.requestedReviewers.isEmpty {
                PreviewMetadataRow(
                    icon: "person.2",
                    label: "Reviewers",
                    value: pullRequest.requestedReviewers.joined(separator: ", ")
                )
            }
            Text(pullRequest.url)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .textSelection(.enabled)
        }
    }

    /// "+120 −30 · 5 files".
    private var changes: String? {
        guard let additions = pullRequest.additions, let deletions = pullRequest.deletions else { return nil }
        var text = "+\(additions) −\(deletions)"
        if let files = pullRequest.changedFiles {
            text += " · \(files) \(files == 1 ? "file" : "files")"
        }
        return text
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: min(date, Date()), relativeTo: Date())
    }
}
