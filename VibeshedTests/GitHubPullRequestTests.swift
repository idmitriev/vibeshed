@testable import Vibeshed
import XCTest

/// The open pull request listing without GitHub or gh: response parsing, the queries,
/// how the module picks its token and refreshes, and the rows it makes.
final class GitHubPullRequestParserTests: XCTestCase {
    private func node(
        _ number: Int, _ title: String, repo: String = "idmitriev/vibeshed", updated: String,
        author: String? = "idmitriev", extra: [String: Any] = [:]
    ) -> [String: Any] {
        var node: [String: Any] = [
            "number": number, "title": title, "url": "https://github.com/\(repo)/pull/\(number)",
            "isDraft": false, "createdAt": "2026-10-01T10:00:00Z", "updatedAt": updated,
            "repository": ["nameWithOwner": repo],
        ]
        if let author {
            node["author"] = ["login": author, "avatarUrl": "https://avatars.example/\(author)"]
        }
        return node.merging(extra) { $1 }
    }

    func testGraphQLMergesFiltersNewestFirst() throws {
        let website = node(81, "Make the website satisfying", updated: "2026-10-12T08:00:00Z", extra: [
            "isDraft": true, "headRefName": "feat/satisfying", "baseRefName": "main",
            "reviewDecision": "CHANGES_REQUESTED", "additions": 120, "deletions": 30, "changedFiles": 5,
            "reviewRequests": ["nodes": [
                ["requestedReviewer": ["login": "alice"]], ["requestedReviewer": ["name": "Design"]],
            ]],
            "commits": ["nodes": [["commit": ["statusCheckRollup": ["state": "FAILURE"]]]]],
        ])
        let other = node(
            12, "Back up MongoDB", repo: "prime-pick/primepick", updated: "2026-10-09T12:00:00Z", author: nil
        )
        let json: [String: Any] = ["data": [
            "viewer": ["login": "idmitriev"],
            "author": ["nodes": [other, website]],
            "review_requested": ["nodes": [website, ["unrelated": true]]],
        ]]

        let listing = try GitHubPullRequestParser.parseGraphQL(json, filters: [.author, .reviewRequested])

        XCTAssertEqual(listing.viewer, "idmitriev")
        XCTAssertEqual(listing.pullRequests.map(\.key), ["idmitriev/vibeshed#81", "prime-pick/primepick#12"])
        let first = listing.pullRequests[0]
        XCTAssertEqual(first.matchedFilters, [.author, .reviewRequested], "found by both searches, listed once")
        XCTAssertTrue(first.isDraft)
        XCTAssertEqual(first.headBranch, "feat/satisfying")
        XCTAssertEqual(first.baseBranch, "main")
        XCTAssertEqual(first.reviewDecision, .changesRequested)
        XCTAssertEqual(first.checks, .failing)
        XCTAssertEqual(first.additions, 120)
        XCTAssertEqual(first.changedFiles, 5)
        XCTAssertEqual(first.requestedReviewers, ["alice", "Design"])
        XCTAssertEqual(first.updatedAt, try Date("2026-10-12T08:00:00Z", strategy: .iso8601))
        XCTAssertEqual(listing.pullRequests[1].author, "ghost", "a deleted account has no author")
        XCTAssertNil(listing.pullRequests[1].checks)
        XCTAssertEqual(listing.pullRequests[1].matchedFilters, [.author])
    }

    func testGraphQLErrorsWithoutData() {
        let rateLimited: [String: Any] = ["errors": [["type": "RATE_LIMITED", "message": "API rate limit exceeded"]]]
        XCTAssertThrowsError(try GitHubPullRequestParser.parseGraphQL(rateLimited, filters: [.author])) { error in
            guard case GitHubError.rateLimited = error else { return XCTFail("\(error)") }
        }
        let broken: [String: Any] = ["errors": [["message": "Field 'x' doesn't exist"]]]
        XCTAssertThrowsError(try GitHubPullRequestParser.parseGraphQL(broken, filters: [.author]))
        XCTAssertThrowsError(try GitHubPullRequestParser.parseGraphQL([1, 2], filters: [.author]))
    }

    /// An org the token isn't SSO-authorized for errors next to the rest of the data.
    func testGraphQLErrorsNextToDataKeepTheData() throws {
        let json: [String: Any] = [
            "data": ["author": ["nodes": [node(1, "One", updated: "2026-10-01T00:00:00Z")]]],
            "errors": [["type": "FORBIDDEN", "message": "Resource protected by organization SAML enforcement"]],
        ]
        let listing = try GitHubPullRequestParser.parseGraphQL(json, filters: [.author])
        XCTAssertEqual(listing.pullRequests.map(\.number), [1])
        XCTAssertNil(listing.viewer)
    }

    func testRESTSearchItems() {
        let json: [String: Any] = ["items": [
            [
                "number": 66, "title": "feat: switch fonts",
                "html_url": "https://github.com/idmitriev/vibeshed/pull/66",
                "repository_url": "https://api.github.com/repos/idmitriev/vibeshed", "pull_request": [:],
                "draft": true, "user": ["login": "idmitriev"], "updated_at": "2026-10-09T00:00:00Z",
            ],
            [
                "number": 5, "title": "An issue", "html_url": "https://github.com/a/b/issues/5",
                "repository_url": "https://api.github.com/repos/a/b",
            ],
        ]]
        let pullRequests = GitHubPullRequestParser.parseSearch(json)
        XCTAssertEqual(pullRequests.map(\.key), ["idmitriev/vibeshed#66"], "issues are left out")
        XCTAssertTrue(pullRequests[0].isDraft)
        XCTAssertNil(pullRequests[0].headBranch)
        XCTAssertNil(pullRequests[0].reviewDecision)
    }

    func testQueries() {
        let query = GitHubPullRequestQuery.graphQL(filters: [.author, .reviewRequested], limit: 50)
        XCTAssertTrue(query.contains(
            #"review_requested: search(type: ISSUE, first: 50, query: "is:pr is:open archived:false "#
                + #"review-requested:@me sort:updated-desc")"#
        ))
        XCTAssertTrue(query.contains("author: search(type: ISSUE"))
        XCTAssertTrue(query.contains("viewer { login }"))
        XCTAssertTrue(query.contains("statusCheckRollup { state }"))
        XCTAssertEqual(
            GitHubPullRequestQuery.ownerSearch(["idmitriev", "prime-pick"]),
            "is:pr is:open archived:false org:idmitriev org:prime-pick"
        )
    }

    func testCheckRollupStates() {
        XCTAssertEqual(GitHubCheckState(rollup: "SUCCESS"), .passing)
        XCTAssertEqual(GitHubCheckState(rollup: "ERROR"), .failing)
        XCTAssertEqual(GitHubCheckState(rollup: "EXPECTED"), .running)
        XCTAssertNil(GitHubCheckState(rollup: nil))
    }
}

final class GitHubPullRequestModuleTests: XCTestCase {
    private let website = GitHubPullRequest(
        number: 81, title: "Make the website satisfying", url: "https://github.com/idmitriev/vibeshed/pull/81/",
        repository: "idmitriev/vibeshed", author: "idmitriev", avatarURL: nil, isDraft: false,
        createdAt: nil, updatedAt: nil, headBranch: "feat/site-polish"
    )

    private func config(_ change: (inout GitHubConfig) -> Void = { _ in }) -> GitHubConfig {
        // No repos: listing them would reach GitHub.
        var config = GitHubConfig(showRepos: false)
        change(&config)
        return config
    }

    /// Waits for the reload a config started, then the listing it started.
    private func settle(_ module: GitHubModule) async {
        if let reload = await module.reloadTask {
            await reload.value
        }
        if let listing = await module.pullRequestTask {
            await listing.value
        }
    }

    private func pullRequestRows(_ module: GitHubModule) async -> [GitHubAction] {
        await module.provideActions(query: "", scoring: ScoringContext(
            usageCounts: [:], lastUsedDates: [:], query: "", systemContext: nil
        ))
        .compactMap { $0 as? GitHubAction }
        .filter { $0.pullRequest != nil }
    }

    func testGitHubCLITokenIsUsedWithoutAConfiguredOne() async {
        let gh = FakeGitHub(token: "gho_cli")
        let module = GitHubModule(tokenReader: gh.readToken, pullRequestFetcher: gh.fetch)
        await module.configDidUpdate(config { $0.ghPath = "/custom/gh" })
        await settle(module)

        XCTAssertEqual(gh.tokenReads, ["/custom/gh"])
        XCTAssertEqual(gh.fetchesWithToken, [true])
        let source = await module.credentialSource
        XCTAssertEqual(source, .githubCLI)
    }

    func testConfiguredTokenWinsAndCLICanBeTurnedOff() async {
        let gh = FakeGitHub(token: "gho_cli")
        let configured = GitHubModule(tokenReader: gh.readToken, pullRequestFetcher: gh.fetch)
        await configured.configDidUpdate(config { $0.token = "ghp_config" })
        await settle(configured)
        XCTAssertEqual(gh.tokenReads, [], "a configured token needs no gh")
        let source = await configured.credentialSource
        XCTAssertEqual(source, .config)

        let off = GitHubModule(tokenReader: gh.readToken, pullRequestFetcher: gh.fetch)
        await off.configDidUpdate(config { $0.useGitHubCLI = false })
        await settle(off)
        XCTAssertEqual(gh.tokenReads, [])
        XCTAssertEqual(gh.fetchesWithToken, [true, false], "without a token it lists by owner instead")
    }

    func testRowsComeFromTheCacheAndRefreshOnceStale() async {
        let gh = FakeGitHub(token: "gho_cli")
        gh.listing = GitHubPullRequestListing(viewer: "idmitriev", pullRequests: [website])
        let module = GitHubModule(tokenReader: gh.readToken, pullRequestFetcher: gh.fetch)
        await module.configDidUpdate(config())
        await settle(module)

        let rows = await pullRequestRows(module)
        XCTAssertEqual(rows.map(\.title), ["Make the website satisfying"])
        _ = await pullRequestRows(module)
        await settle(module)
        XCTAssertEqual(gh.fetchCount, 1, "a fresh listing answers without listing again")

        await module.configDidUpdate(config { $0.pullRequestRefresh = 0 })
        _ = await pullRequestRows(module)
        await settle(module)
        XCTAssertEqual(gh.fetchCount, 2, "a stale listing refreshes on the next picker open")
    }

    func testFailureKeepsTheLastListingAndAsksGitHubCLIAgain() async {
        let gh = FakeGitHub(token: "gho_cli")
        gh.listing = GitHubPullRequestListing(viewer: "idmitriev", pullRequests: [website])
        let module = GitHubModule(tokenReader: gh.readToken, pullRequestFetcher: gh.fetch)
        await module.configDidUpdate(config { $0.pullRequestRefresh = 0 })
        await settle(module)

        gh.error = GitHubError.invalidToken
        await module.refreshPullRequestsIfDue()
        await settle(module)
        XCTAssertEqual(gh.fetchCount, 2)
        let stale = await module.credentialsStale
        XCTAssertTrue(stale)

        // The next picker open shows the last rows and asks gh again.
        gh.error = nil
        let rows = await pullRequestRows(module)
        XCTAssertEqual(rows.count, 1, "an error leaves the rows as they were")
        await settle(module)
        XCTAssertEqual(gh.tokenReads.count, 2, "gh's token is read again once it stops working")
        XCTAssertEqual(gh.fetchCount, 3)
        let isStale = await module.credentialsStale
        XCTAssertFalse(isStale)
    }

    func testHiddenPullRequestsAreNeitherListedNorShown() async {
        let gh = FakeGitHub(token: "gho_cli")
        gh.listing = GitHubPullRequestListing(viewer: nil, pullRequests: [website])
        let module = GitHubModule(tokenReader: gh.readToken, pullRequestFetcher: gh.fetch)
        await module.configDidUpdate(config { $0.showPullRequests = false })
        await settle(module)
        let rows = await pullRequestRows(module)
        XCTAssertEqual(rows.count, 0)
        XCTAssertEqual(gh.fetchCount, 0)
    }

    func testOwnersWithoutAToken() {
        XCTAssertEqual(GitHubModule.pullRequestOwners(GitHubConfig(defaultOwner: "me")), ["me"])
        let both = GitHubConfig(defaultOwner: "me", repoOwners: ["a", "b"])
        XCTAssertEqual(GitHubModule.pullRequestOwners(both), ["a", "b"])
        XCTAssertEqual(GitHubModule.pullRequestOwners(GitHubConfig()), [])
    }

    // MARK: - Rows

    func testRowMatchesOnWordsAndOpensThePullRequest() {
        let row = GitHubModule.pullRequestAction(website, index: 0, viewer: "idmitriev", eventBus: nil)
        XCTAssertEqual(row.id, GitHubModule.pullRequestActionID(website))
        XCTAssertEqual(row.id.rawValue, "github/pr.\(StableID.hash("idmitriev/vibeshed#81"))")
        XCTAssertEqual(row.subtitle, "idmitriev/vibeshed #81")
        XCTAssertTrue(row.requiresWordPrefixMatch)
        XCTAssertEqual(row.keywords, ["feat", "site", "polish"])
        XCTAssertFalse(row.keywords.contains("pr"))
        XCTAssertEqual(row.deduplicationKey, "https://github.com/idmitriev/vibeshed/pull/81")
        XCTAssertEqual(row.htmlURL, website.url)
        XCTAssertLessThan(row.relevanceScore, 0.6, "below apps")
        XCTAssertGreaterThan(
            row.relevanceScore,
            GitHubModule.pullRequestAction(website, index: 5, viewer: nil, eventBus: nil).relevanceScore
        )
    }

    func testSubtitleNamesOthersAndWhatNeedsAttention() {
        var pullRequest = website
        XCTAssertEqual(
            GitHubModule.pullRequestSubtitle(pullRequest, viewer: "bob"), "idmitriev/vibeshed #81 · by idmitriev"
        )
        pullRequest.checks = .failing
        pullRequest.reviewDecision = .approved
        XCTAssertEqual(GitHubModule.pullRequestStatus(pullRequest), "Checks failing")
        pullRequest.checks = .passing
        XCTAssertEqual(GitHubModule.pullRequestStatus(pullRequest), "Approved")
        pullRequest.matchedFilters = [.reviewRequested]
        XCTAssertEqual(GitHubModule.pullRequestStatus(pullRequest), "Review requested")
        pullRequest.reviewDecision = .reviewRequired
        pullRequest.matchedFilters = []
        XCTAssertNil(GitHubModule.pullRequestStatus(pullRequest))
    }

    func testValidation() {
        XCTAssertTrue(GitHubModule.validate(GitHubConfig()).isValid)
        let invalid = GitHubModule.validate(GitHubConfig(
            ghPath: " ", pullRequestFilters: ["author", "reviewer"], maxPullRequests: 0, pullRequestRefresh: 5
        ))
        XCTAssertEqual(invalid.errors.count, 4, "\(invalid.errors)")
        XCTAssertTrue(invalid.errors.contains { $0.contains("'reviewer'") })
        XCTAssertFalse(GitHubModule.validate(GitHubConfig(pullRequestFilters: [])).isValid)
        XCTAssertTrue(GitHubModule.validate(GitHubConfig(showPullRequests: false, pullRequestFilters: [])).isValid)
    }
}

/// Stands in for gh and GitHub, recording what the module asked.
private final class FakeGitHub: @unchecked Sendable {
    private let lock = NSLock()
    private let token: String?
    private var reads: [String?] = []
    private var fetches: [Bool] = []
    private var currentListing = GitHubPullRequestListing.empty
    private var currentError: Error?

    init(token: String?) {
        self.token = token
    }

    var tokenReads: [String?] {
        lock.withLock { reads }
    }

    var fetchesWithToken: [Bool] {
        lock.withLock { fetches }
    }

    var fetchCount: Int {
        fetchesWithToken.count
    }

    var listing: GitHubPullRequestListing {
        get { lock.withLock { currentListing } }
        set { lock.withLock { currentListing = newValue } }
    }

    var error: Error? {
        get { lock.withLock { currentError } }
        set { lock.withLock { currentError = newValue } }
    }

    var readToken: @Sendable (String?) async -> String? {
        { [self] path in recordRead(path) }
    }

    var fetch: @Sendable (GitHubAPIClient, GitHubConfig) async throws -> GitHubPullRequestListing {
        { [self] client, _ in try recordFetch(hasToken: client.hasToken) }
    }

    private func recordRead(_ path: String?) -> String? {
        lock.withLock {
            reads.append(path)
            return token
        }
    }

    private func recordFetch(hasToken: Bool) throws -> GitHubPullRequestListing {
        try lock.withLock {
            fetches.append(hasToken)
            if let currentError {
                throw currentError
            }
            return currentListing
        }
    }
}
