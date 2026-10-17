import Foundation

// MARK: - Model

/// Which of the signed-in user's open pull requests to list, by the GitHub search
/// qualifier each one stands for (`author` → `author:@me`).
enum GitHubPullRequestFilter: String, CaseIterable, Sendable {
    case author
    case reviewRequested = "review-requested"
    case assignee
    case involves
    case mentions

    var qualifier: String {
        "\(rawValue):@me"
    }

    /// The GraphQL alias of this filter's search: names allow no dashes.
    var alias: String {
        rawValue.replacingOccurrences(of: "-", with: "_")
    }
}

enum GitHubReviewDecision: String, Sendable {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case reviewRequired = "REVIEW_REQUIRED"
}

/// The combined state of a pull request's latest commit checks and statuses.
enum GitHubCheckState: Sendable {
    case passing
    case failing
    case running

    init?(rollup: String?) {
        switch rollup {
        case "SUCCESS": self = .passing
        case "FAILURE", "ERROR": self = .failing
        case "PENDING", "EXPECTED": self = .running
        default: return nil
        }
    }
}

/// One open pull request listed in the main search. GraphQL fills in everything; the
/// REST search used without a token leaves branches, review and checks unknown.
struct GitHubPullRequest: Sendable, Equatable {
    let number: Int
    let title: String
    let url: String
    /// `owner/name`.
    let repository: String
    let author: String
    let avatarURL: String?
    let isDraft: Bool
    let createdAt: Date?
    let updatedAt: Date?
    var headBranch: String?
    var baseBranch: String?
    var reviewDecision: GitHubReviewDecision?
    var checks: GitHubCheckState?
    var additions: Int?
    var deletions: Int?
    var changedFiles: Int?
    var requestedReviewers: [String] = []
    /// The filters whose search found it.
    var matchedFilters: Set<GitHubPullRequestFilter> = []

    /// `owner/name#123`: unique across repos, and stable for the life of the pull request.
    var key: String {
        "\(repository)#\(number)"
    }
}

/// What one refresh lists: the pull requests, newest update first, and whose they are.
struct GitHubPullRequestListing: Sendable, Equatable {
    /// The signed-in user; nil when listed without a token.
    var viewer: String?
    var pullRequests: [GitHubPullRequest]

    static let empty = GitHubPullRequestListing(viewer: nil, pullRequests: [])
}

// MARK: - Fetching

extension GitHubAPIClient {
    /// The signed-in user's open pull requests, one GraphQL request for all `filters`
    /// (each its own aliased search of up to `limit`). Needs a token: `@me` means nothing
    /// without one.
    func openPullRequests(
        filters: [GitHubPullRequestFilter],
        limit: Int
    ) async throws -> GitHubPullRequestListing {
        guard hasToken else { throw GitHubError.invalidToken }
        guard !filters.isEmpty else { return .empty }
        var request = try makeRequest(path: "/graphql", queryItems: [])
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["query": GitHubPullRequestQuery.graphQL(filters: filters, limit: limit)]
        )
        let json = try await performRequest(request)
        return try GitHubPullRequestParser.parseGraphQL(json, filters: filters)
    }

    /// Open pull requests in the repos of `owners`, through the REST search, which works
    /// without a token (public repos only, then).
    func openPullRequests(owners: [String], limit: Int) async throws -> GitHubPullRequestListing {
        let owners = owners.filter { !$0.isEmpty }
        guard !owners.isEmpty else { return .empty }
        let request = try makeRequest(
            path: "/search/issues",
            queryItems: [
                ("q", GitHubPullRequestQuery.ownerSearch(owners)),
                ("per_page", "\(limit)"),
                ("sort", "updated"),
            ]
        )
        let json = try await performRequest(request)
        return GitHubPullRequestListing(viewer: nil, pullRequests: GitHubPullRequestParser.parseSearch(json))
    }
}

// MARK: - Queries

enum GitHubPullRequestQuery {
    /// Several `org:` qualifiers in one search match any of them.
    static func ownerSearch(_ owners: [String]) -> String {
        "is:pr is:open archived:false " + owners.map { "org:\($0)" }.joined(separator: " ")
    }

    static func search(_ filter: GitHubPullRequestFilter) -> String {
        "is:pr is:open archived:false \(filter.qualifier) sort:updated-desc"
    }

    static func graphQL(filters: [GitHubPullRequestFilter], limit: Int) -> String {
        let searches = filters.map { filter in
            """
              \(filter.alias): search(type: ISSUE, first: \(limit), query: "\(search(filter))") {
                nodes { ...OpenPullRequest }
              }
            """
        }
        return """
        query {
          viewer { login }
        \(searches.joined(separator: "\n"))
        }

        fragment OpenPullRequest on PullRequest {
          number title url isDraft createdAt updatedAt
          author { login avatarUrl }
          repository { nameWithOwner }
          headRefName baseRefName reviewDecision
          additions deletions changedFiles
          reviewRequests(first: 10) {
            nodes { requestedReviewer { ... on User { login } ... on Team { name } ... on Bot { login } } }
          }
          commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
        }
        """
    }
}

// MARK: - Parsing

enum GitHubPullRequestParser {
    /// A GraphQL answer: each filter's search merged into one list, a pull request found
    /// by several of them listed once with all of them, newest update first. Errors next
    /// to data (an SSO org the token isn't authorized for) still use the data.
    static func parseGraphQL(_ json: Any, filters: [GitHubPullRequestFilter]) throws -> GitHubPullRequestListing {
        guard let root = json as? [String: Any] else { throw GitHubError.parseFailed }
        let errors = root["errors"] as? [[String: Any]] ?? []
        guard let data = root["data"] as? [String: Any] else {
            if errors.contains(where: { $0["type"] as? String == "RATE_LIMITED" }) {
                throw GitHubError.rateLimited(resetDate: nil)
            }
            let message = errors.compactMap { $0["message"] as? String }.joined(separator: "; ")
            throw GitHubError.apiError(statusCode: 200, message: message.isEmpty ? "No data" : message)
        }

        var byKey: [String: GitHubPullRequest] = [:]
        for filter in filters {
            let search = data[filter.alias] as? [String: Any]
            let nodes = search?["nodes"] as? [[String: Any]] ?? []
            for node in nodes {
                guard var pullRequest = parseNode(node) else { continue }
                pullRequest.matchedFilters = byKey[pullRequest.key]?.matchedFilters ?? []
                pullRequest.matchedFilters.insert(filter)
                byKey[pullRequest.key] = pullRequest
            }
        }
        let viewer = (data["viewer"] as? [String: Any])?["login"] as? String
        return GitHubPullRequestListing(viewer: viewer, pullRequests: newestFirst(Array(byKey.values)))
    }

    private static func parseNode(_ node: [String: Any]) -> GitHubPullRequest? {
        guard let number = node["number"] as? Int,
              let title = node["title"] as? String,
              let url = node["url"] as? String,
              let repository = (node["repository"] as? [String: Any])?["nameWithOwner"] as? String
        else { return nil }
        // A deleted account's pull requests have no author.
        let author = node["author"] as? [String: Any]
        let reviewers = (node["reviewRequests"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
        let commits = (node["commits"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
        let rollup = ((commits.last?["commit"] as? [String: Any])?["statusCheckRollup"] as? [String: Any])?["state"]
        var pullRequest = GitHubPullRequest(
            number: number,
            title: title,
            url: url,
            repository: repository,
            author: author?["login"] as? String ?? "ghost",
            avatarURL: author?["avatarUrl"] as? String,
            isDraft: node["isDraft"] as? Bool ?? false,
            createdAt: date(node["createdAt"]),
            updatedAt: date(node["updatedAt"])
        )
        pullRequest.headBranch = node["headRefName"] as? String
        pullRequest.baseBranch = node["baseRefName"] as? String
        pullRequest.reviewDecision = (node["reviewDecision"] as? String).flatMap(GitHubReviewDecision.init)
        pullRequest.checks = GitHubCheckState(rollup: rollup as? String)
        pullRequest.additions = node["additions"] as? Int
        pullRequest.deletions = node["deletions"] as? Int
        pullRequest.changedFiles = node["changedFiles"] as? Int
        pullRequest.requestedReviewers = reviewers.compactMap { request in
            let reviewer = request["requestedReviewer"] as? [String: Any]
            return reviewer?["login"] as? String ?? reviewer?["name"] as? String
        }
        return pullRequest
    }

    /// REST search items (`/search/issues`), which have no branches, review or checks.
    static func parseSearch(_ json: Any) -> [GitHubPullRequest] {
        let items = (json as? [String: Any])?["items"] as? [[String: Any]] ?? []
        let pullRequests = items.compactMap { item -> GitHubPullRequest? in
            guard item["pull_request"] != nil,
                  let number = item["number"] as? Int,
                  let title = item["title"] as? String,
                  let url = item["html_url"] as? String,
                  let repositoryURL = item["repository_url"] as? String
            else { return nil }
            let user = item["user"] as? [String: Any]
            return GitHubPullRequest(
                number: number,
                title: title,
                url: url,
                repository: repositoryURL.components(separatedBy: "/repos/").last ?? repositoryURL,
                author: user?["login"] as? String ?? "ghost",
                avatarURL: user?["avatar_url"] as? String,
                isDraft: item["draft"] as? Bool ?? false,
                createdAt: date(item["created_at"]),
                updatedAt: date(item["updated_at"])
            )
        }
        return newestFirst(pullRequests)
    }

    private static func newestFirst(_ pullRequests: [GitHubPullRequest]) -> [GitHubPullRequest] {
        pullRequests.sorted {
            ($0.updatedAt ?? .distantPast, $0.key) > ($1.updatedAt ?? .distantPast, $1.key)
        }
    }

    private static func date(_ value: Any?) -> Date? {
        (value as? String).flatMap { try? Date($0, strategy: .iso8601) }
    }
}
