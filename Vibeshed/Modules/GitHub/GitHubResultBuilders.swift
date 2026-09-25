import AppKit
import SwiftUI

// MARK: - Result Builders & Helpers

extension GitHubModule {
    static func buildRepoResults(
        _ repos: [GitHubRepo],
        eventBus: EventBus?
    ) -> [GitHubAction] {
        repos.enumerated().map { index, repo in
            let subtitle = repoSubtitle(repo)
            return GitHubAction(
                id: ActionID(
                    module: "github",
                    name: "result.repo.\(repo.id)"
                ),
                title: repo.fullName,
                subtitle: subtitle,
                iconName: "folder",
                relevanceScore: rankedScore(index: index, step: 0.03),
                keywords: [
                    "repo", repo.fullName.lowercased(),
                    repo.language?.lowercased(),
                ].compactMap { $0 },
                avatarURL: repo.avatarURL,
                githubItemType: .repo,
                htmlURL: repo.htmlURL,
                itemDescription: repo.description,
                repoStars: repo.stars,
                repoLanguage: repo.language
            ) { [eventBus] _ in
                await openURL(repo.htmlURL, via: eventBus)
                return .dismiss
            }
        }
    }

    static func buildIssueResults(
        _ issues: [GitHubIssue],
        eventBus: EventBus?
    ) -> [GitHubAction] {
        issues.enumerated().map { index, issue in
            let (icon, color) = issueStateVisuals(issue.state)
            return GitHubAction(
                id: ActionID(
                    module: "github",
                    name: "result.issue.\(issue.id)"
                ),
                title: "#\(issue.number) \(issue.title)",
                subtitle: "\(issue.repoFullName) by \(issue.author)",
                iconName: "exclamationmark.circle",
                relevanceScore: rankedScore(index: index, step: 0.03),
                keywords: [
                    "issue", issue.title.lowercased(),
                    issue.repoFullName.lowercased(),
                ],
                avatarURL: issue.avatarURL,
                githubItemType: .issue,
                htmlURL: issue.htmlURL,
                stateIcon: icon,
                stateColor: color,
                itemDescription: issue.body.map { String($0.prefix(200)) },
                labels: issue.labels.isEmpty ? nil : issue.labels,
                createdAt: issue.createdAt
            ) { [eventBus] _ in
                await openURL(issue.htmlURL, via: eventBus)
                return .dismiss
            }
        }
    }

    static func buildPRResults(
        _ prs: [GitHubPR],
        eventBus: EventBus?
    ) -> [GitHubAction] {
        prs.enumerated().map { index, pr in
            let (icon, color) = prStateVisuals(pr)
            return GitHubAction(
                id: ActionID(
                    module: "github",
                    name: "result.pr.\(pr.id)"
                ),
                title: "#\(pr.number) \(pr.title)",
                subtitle: "\(pr.repoFullName) by \(pr.author)",
                iconName: "arrow.triangle.pull",
                relevanceScore: rankedScore(index: index, step: 0.03),
                keywords: [
                    "pr", "pull", pr.title.lowercased(),
                    pr.repoFullName.lowercased(),
                ],
                avatarURL: pr.avatarURL,
                githubItemType: .pr,
                htmlURL: pr.htmlURL,
                stateIcon: icon,
                stateColor: color,
                itemDescription: pr.body.map { String($0.prefix(200)) },
                createdAt: pr.createdAt
            ) { [eventBus] _ in
                await openURL(pr.htmlURL, via: eventBus)
                return .dismiss
            }
        }
    }

    static func buildNotificationResults(
        _ notifications: [GitHubNotification],
        eventBus: EventBus?
    ) -> [GitHubAction] {
        notifications.enumerated().map { index, note in
            let icon = notificationIcon(note.type)
            return GitHubAction(
                id: ActionID(
                    module: "github",
                    name: "result.notification.\(note.id)"
                ),
                title: note.title,
                subtitle: "\(note.repoFullName) · \(note.reason)",
                iconName: icon,
                relevanceScore: rankedScore(index: index, step: 0.03),
                keywords: [
                    "notification", note.title.lowercased(),
                    note.repoFullName.lowercased(),
                ],
                githubItemType: .notification,
                htmlURL: note.htmlURL
            ) { [eventBus] _ in
                if let htmlURL = note.htmlURL {
                    await openURL(htmlURL, via: eventBus)
                }
                return .dismiss
            }
        }
    }

    static func openURL(_ urlString: String, via eventBus: EventBus?) async {
        guard let url = URL(string: urlString) else { return }
        if let eventBus {
            await eventBus.publish(.openURL(url))
        } else {
            await MainActor.run { _ = NSWorkspace.shared.open(url) }
        }
    }

    static func repoSubtitle(_ repo: GitHubRepo) -> String {
        var parts: [String] = []
        if let desc = repo.description, !desc.isEmpty {
            let truncated = desc.prefix(60)
            parts.append(
                truncated.count < desc.count
                    ? "\(truncated)..." : String(truncated)
            )
        }
        if let lang = repo.language {
            parts.append(lang)
        }
        if repo.stars > 0 {
            parts.append("\(formatCount(repo.stars)) stars")
        }
        return parts.joined(separator: " · ")
    }

    static func formatCount(_ count: Int) -> String {
        if count >= 1000 {
            let thousands = Double(count) / 1000.0
            return String(format: "%.1fk", thousands)
        }
        return "\(count)"
    }

    static func issueStateVisuals(
        _ state: String
    ) -> (String, Color) {
        switch state {
        case "open": ("circle.fill", .green)
        case "closed": ("checkmark.circle.fill", .purple)
        default: ("circle", .secondary)
        }
    }

    static func prStateVisuals(
        _ pr: GitHubPR
    ) -> (String, Color) {
        if pr.mergedAt != nil {
            return ("arrow.triangle.merge", .purple)
        }
        if pr.state == "closed" {
            return ("xmark.circle.fill", .red)
        }
        if pr.draft {
            return ("doc", .gray)
        }
        return ("arrow.triangle.pull", .green)
    }

    static func notificationIcon(_ type: String) -> String {
        switch type {
        case "PullRequest": "arrow.triangle.pull"
        case "Issue": "exclamationmark.circle"
        case "Release": "tag"
        case "Discussion": "bubble.left.and.bubble.right"
        default: "bell"
        }
    }
}
