import Foundation

// MARK: - Response Types

struct GitHubRepo: Sendable {
    let id: Int
    let fullName: String
    let description: String?
    let htmlURL: String
    let language: String?
    let stars: Int
    let forks: Int
    let avatarURL: String?
}

struct GitHubIssue: Sendable {
    let id: Int
    let number: Int
    let title: String
    let body: String?
    let htmlURL: String
    let state: String
    let repoFullName: String
    let author: String
    let labels: [String]
    let createdAt: String
    let avatarURL: String?
}

struct GitHubPR: Sendable {
    let id: Int
    let number: Int
    let title: String
    let body: String?
    let htmlURL: String
    let state: String
    let repoFullName: String
    let author: String
    let draft: Bool
    let createdAt: String
    let mergedAt: String?
    let avatarURL: String?
}

struct GitHubNotification: Sendable {
    let id: String
    let title: String
    let type: String
    let reason: String
    let repoFullName: String
    let htmlURL: String?
    let updatedAt: String
}

// MARK: - Errors

enum GitHubError: Error, LocalizedError {
    case invalidToken
    case rateLimited(resetDate: Date?)
    case apiError(statusCode: Int, message: String)
    case networkError(Error)
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .invalidToken:
            return "GitHub token is invalid or expired"
        case .rateLimited(let reset):
            if let reset {
                let formatter = RelativeDateTimeFormatter()
                let relative = formatter.localizedString(
                    for: reset, relativeTo: Date()
                )
                return "GitHub rate limit exceeded. Resets \(relative)"
            }
            return "GitHub rate limit exceeded"
        case .apiError(let code, let msg):
            return "GitHub API error \(code): \(msg)"
        case .networkError(let err):
            return "Network error: \(err.localizedDescription)"
        case .parseFailed:
            return "Failed to parse GitHub API response"
        }
    }
}

// MARK: - API Client

final class GitHubAPIClient: @unchecked Sendable {
    private let token: String?
    private let baseURL = "https://api.github.com"

    init(token: String?) {
        self.token = token
    }

    // MARK: - Public

    func searchRepos(
        query: String,
        defaultOwner: String?,
        limit: Int
    ) async throws -> [GitHubRepo] {
        let q = scopedQuery(query, defaultOwner: defaultOwner)
        let request = try makeRequest(
            path: "/search/repositories",
            queryItems: [("q", q), ("per_page", "\(limit)"), ("sort", "stars")]
        )
        let json = try await performRequest(request)
        return parseRepos(json)
    }

    func searchIssues(
        query: String,
        defaultOwner: String?,
        limit: Int
    ) async throws -> [GitHubIssue] {
        let q = scopedQuery(query, defaultOwner: defaultOwner) + " is:issue"
        let request = try makeRequest(
            path: "/search/issues",
            queryItems: [("q", q), ("per_page", "\(limit)"), ("sort", "updated")]
        )
        let json = try await performRequest(request)
        return parseIssues(json)
    }

    func searchPRs(
        query: String,
        defaultOwner: String?,
        limit: Int
    ) async throws -> [GitHubPR] {
        let q = scopedQuery(query, defaultOwner: defaultOwner) + " is:pr"
        let request = try makeRequest(
            path: "/search/issues",
            queryItems: [("q", q), ("per_page", "\(limit)"), ("sort", "updated")]
        )
        let json = try await performRequest(request)
        return parsePRs(json)
    }

    func listNotifications(limit: Int) async throws -> [GitHubNotification] {
        guard token != nil else {
            throw GitHubError.invalidToken
        }
        let request = try makeRequest(
            path: "/notifications",
            queryItems: [("per_page", "\(limit)"), ("all", "false")]
        )
        let json = try await performRequest(request)
        return parseNotifications(json)
    }

    // MARK: - Private: Request Building

    private func scopedQuery(
        _ query: String,
        defaultOwner: String?
    ) -> String {
        guard let owner = defaultOwner,
              !owner.isEmpty,
              !query.contains("org:"),
              !query.contains("user:"),
              !query.contains("repo:")
        else {
            return query
        }
        return "org:\(owner) \(query)"
    }

    private func makeRequest(
        path: String,
        queryItems: [(String, String)]
    ) throws -> URLRequest {
        var components = URLComponents(string: baseURL + path)!
        components.queryItems = queryItems.map {
            URLQueryItem(name: $0.0, value: $0.1)
        }
        guard let url = components.url else {
            throw GitHubError.parseFailed
        }
        var request = URLRequest(url: url)
        request.setValue(
            "application/vnd.github+json",
            forHTTPHeaderField: "Accept"
        )
        request.setValue(
            "2022-11-28",
            forHTTPHeaderField: "X-GitHub-Api-Version"
        )
        if let token, !token.isEmpty {
            request.setValue(
                "Bearer \(token)",
                forHTTPHeaderField: "Authorization"
            )
        }
        return request
    }

    private func performRequest(_ request: URLRequest) async throws -> Any {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw GitHubError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GitHubError.parseFailed
        }

        if http.statusCode == 401 {
            throw GitHubError.invalidToken
        }

        if http.statusCode == 403 || http.statusCode == 429 {
            let resetDate = rateLimitResetDate(from: http)
            let remaining = http.value(
                forHTTPHeaderField: "X-RateLimit-Remaining"
            )
            if remaining == "0" {
                throw GitHubError.rateLimited(resetDate: resetDate)
            }
        }

        if !(200 ... 299).contains(http.statusCode) {
            let message = extractErrorMessage(from: data)
            throw GitHubError.apiError(
                statusCode: http.statusCode, message: message
            )
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            throw GitHubError.parseFailed
        }
        return json
    }

    private func rateLimitResetDate(from response: HTTPURLResponse) -> Date? {
        guard let resetStr = response.value(
            forHTTPHeaderField: "X-RateLimit-Reset"
        ),
            let resetTimestamp = TimeInterval(resetStr)
        else { return nil }
        return Date(timeIntervalSince1970: resetTimestamp)
    }

    private func extractErrorMessage(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data)
            as? [String: Any],
            let message = json["message"] as? String
        else {
            return "Unknown error"
        }
        return message
    }

    // MARK: - Private: Parsing

    private func parseSearchItems(_ json: Any) -> [[String: Any]] {
        guard let dict = json as? [String: Any],
              let items = dict["items"] as? [[String: Any]]
        else { return [] }
        return items
    }

    private func parseRepos(_ json: Any) -> [GitHubRepo] {
        parseSearchItems(json).compactMap(parseRepo)
    }

    private func parseRepo(_ item: [String: Any]) -> GitHubRepo? {
        guard let id = item["id"] as? Int,
              let fullName = item["full_name"] as? String,
              let htmlURL = item["html_url"] as? String
        else { return nil }
        let owner = item["owner"] as? [String: Any]
        return GitHubRepo(
            id: id,
            fullName: fullName,
            description: item["description"] as? String,
            htmlURL: htmlURL,
            language: item["language"] as? String,
            stars: item["stargazers_count"] as? Int ?? 0,
            forks: item["forks_count"] as? Int ?? 0,
            avatarURL: owner?["avatar_url"] as? String
        )
    }

    private func parseIssues(_ json: Any) -> [GitHubIssue] {
        parseSearchItems(json).compactMap(parseIssue)
    }

    private func parseIssue(_ item: [String: Any]) -> GitHubIssue? {
        guard let id = item["id"] as? Int,
              let number = item["number"] as? Int,
              let title = item["title"] as? String,
              let htmlURL = item["html_url"] as? String,
              let state = item["state"] as? String
        else { return nil }
        let user = item["user"] as? [String: Any]
        let labelObjs = item["labels"] as? [[String: Any]] ?? []
        let labels = labelObjs.compactMap { $0["name"] as? String }
        return GitHubIssue(
            id: id,
            number: number,
            title: title,
            body: item["body"] as? String,
            htmlURL: htmlURL,
            state: state,
            repoFullName: repoFullName(from: item),
            author: user?["login"] as? String ?? "unknown",
            labels: labels,
            createdAt: item["created_at"] as? String ?? "",
            avatarURL: user?["avatar_url"] as? String
        )
    }

    private func parsePRs(_ json: Any) -> [GitHubPR] {
        parseSearchItems(json).compactMap(parsePR)
    }

    private func parsePR(_ item: [String: Any]) -> GitHubPR? {
        guard let id = item["id"] as? Int,
              let number = item["number"] as? Int,
              let title = item["title"] as? String,
              let htmlURL = item["html_url"] as? String,
              let state = item["state"] as? String
        else { return nil }
        let user = item["user"] as? [String: Any]
        let prObj = item["pull_request"] as? [String: Any]
        return GitHubPR(
            id: id,
            number: number,
            title: title,
            body: item["body"] as? String,
            htmlURL: htmlURL,
            state: state,
            repoFullName: repoFullName(from: item),
            author: user?["login"] as? String ?? "unknown",
            draft: item["draft"] as? Bool ?? false,
            createdAt: item["created_at"] as? String ?? "",
            mergedAt: prObj?["merged_at"] as? String,
            avatarURL: user?["avatar_url"] as? String
        )
    }

    private func parseNotifications(_ json: Any) -> [GitHubNotification] {
        guard let items = json as? [[String: Any]] else { return [] }
        return items.compactMap(parseNotification)
    }

    private func parseNotification(
        _ item: [String: Any]
    ) -> GitHubNotification? {
        guard let id = item["id"] as? String,
              let subject = item["subject"] as? [String: Any],
              let title = subject["title"] as? String,
              let type = subject["type"] as? String
        else { return nil }
        let repo = item["repository"] as? [String: Any]
        let repoFullName = repo?["full_name"] as? String ?? ""
        let htmlURL = reconstructHTMLURL(
            from: subject["url"] as? String,
            repoFullName: repoFullName
        )
        return GitHubNotification(
            id: id,
            title: title,
            type: type,
            reason: item["reason"] as? String ?? "",
            repoFullName: repoFullName,
            htmlURL: htmlURL,
            updatedAt: item["updated_at"] as? String ?? ""
        )
    }

    // MARK: - Private: Helpers

    private func repoFullName(from item: [String: Any]) -> String {
        if let repoURL = item["repository_url"] as? String {
            let prefix = "https://api.github.com/repos/"
            if repoURL.hasPrefix(prefix) {
                return String(repoURL.dropFirst(prefix.count))
            }
        }
        return ""
    }

    private func reconstructHTMLURL(
        from apiURL: String?,
        repoFullName: String
    ) -> String? {
        guard let apiURL else { return nil }
        let prefix = "https://api.github.com/repos/"
        if apiURL.hasPrefix(prefix) {
            let path = String(apiURL.dropFirst(prefix.count))
            return "https://github.com/\(path)"
        }
        if !repoFullName.isEmpty {
            return "https://github.com/\(repoFullName)"
        }
        return nil
    }
}
