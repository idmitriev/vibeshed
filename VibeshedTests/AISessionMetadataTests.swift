import Foundation
@testable import Vibeshed
import XCTest

/// The model and branch shown in a session's preview, read from the fixture trees in
/// `Fixtures/AISessions`, which mirror the on-disk layouts of `~/.claude`, Claude
/// Desktop's `claude-code-sessions` and `~/.codex`.
final class AISessionMetadataTests: XCTestCase {
    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/AISessions")

    private func claudeSessions() -> [String: AISession] {
        let sessions = AnthropicSessionReader.readSessions(
            sources: ["claudeCode", "claudeDesktop"],
            limit: 20,
            locations: AnthropicSessionReader.Locations(
                claudeDirectory: Self.fixtures.appendingPathComponent("claude"),
                desktopSessionsDirectory: Self.fixtures
                    .appendingPathComponent("desktop")
            )
        )
        return Dictionary(
            uniqueKeysWithValues: sessions.map { ($0.sessionID, $0) }
        )
    }

    private func codexSessions() -> [String: AISession] {
        let sessions = OpenAISessionReader.readSessions(
            limit: 20, root: Self.fixtures.appendingPathComponent("codex")
        )
        return Dictionary(
            uniqueKeysWithValues: sessions.map { ($0.sessionID, $0) }
        )
    }

    // MARK: - Claude Code

    /// The transcript ends with a synthetic API-error message, a subagent turn on
    /// another model and branch, and bookkeeping records. None of them describe the
    /// session; the main-chain turn before them does.
    func testClaudeCodeReadsNewestMainChainModelAndBranch() throws {
        let session = try XCTUnwrap(
            claudeSessions()["11111111-1111-4111-8111-111111111111"]
        )
        XCTAssertEqual(session.model, "Opus 5.5")
        XCTAssertEqual(session.branch, "feat/preview-rows")
        XCTAssertEqual(session.project, "/tmp/vibeshed")
        XCTAssertEqual(session.source, AnthropicProvider.claudeCode)
    }

    func testClaudeCodeSessionPredatingBranchesHasModelOnly() throws {
        let session = try XCTUnwrap(
            claudeSessions()["22222222-2222-4222-8222-222222222222"]
        )
        XCTAssertEqual(session.model, "Sonnet 3.5")
        XCTAssertNil(session.branch)
    }

    /// The newest turn ran on a detached checkout. An earlier branch must not be shown
    /// in its place: it is no longer what the session is on.
    func testClaudeCodeDetachedHeadShowsNoBranch() throws {
        let session = try XCTUnwrap(
            claudeSessions()["33333333-3333-4333-8333-333333333333"]
        )
        XCTAssertEqual(session.model, "Fable 5.1")
        XCTAssertNil(session.branch)
    }

    /// Claude Code prunes old transcripts while `history.jsonl` keeps the prompts.
    func testClaudeCodeSessionWithoutTranscriptHasNoModelOrBranch() throws {
        let session = try XCTUnwrap(
            claudeSessions()["44444444-4444-4444-8444-444444444444"]
        )
        XCTAssertNil(session.model)
        XCTAssertNil(session.branch)
    }

    func testTranscriptIndexSkipsSubagentDirectories() throws {
        let projects = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: projects) }
        let subagents = projects
            .appendingPathComponent("-tmp-app/abc/subagents")
        try FileManager.default.createDirectory(
            at: subagents, withIntermediateDirectories: true
        )
        try Data().write(
            to: projects.appendingPathComponent("-tmp-app/abc.jsonl")
        )
        try Data().write(to: subagents.appendingPathComponent("agent-1.jsonl"))

        let index = AnthropicTranscripts.transcriptPaths(in: projects)
        XCTAssertEqual(Array(index.keys), ["abc"])
    }

    // MARK: - Claude Desktop

    /// The worktree's branch was renamed after the app recorded it, so the
    /// transcript's newer values win over the session metadata.
    func testDesktopSessionPrefersTranscriptOverMetadata() throws {
        let session = try XCTUnwrap(
            claudeSessions()["local_55555555-5555-4555-8555-555555555555"]
        )
        XCTAssertEqual(session.model, "Sonnet 5.5")
        XCTAssertEqual(session.branch, "feat/renamed-in-worktree")
    }

    func testDesktopSessionFallsBackToMetadata() throws {
        let session = try XCTUnwrap(
            claudeSessions()["local_77777777-7777-4777-8777-777777777777"]
        )
        XCTAssertEqual(session.model, "Opus 4.6")
        XCTAssertEqual(session.branch, "claude/kept-worktree")
    }

    // MARK: - Codex

    /// The thread switched models mid-way; the preview shows the one it last ran on.
    func testCodexReadsBranchFromHeaderAndModelFromLatestTurn() throws {
        let session = try XCTUnwrap(
            codexSessions()["0199aaaa-0000-7000-8000-000000000001"]
        )
        XCTAssertEqual(session.title, "Add preview rows")
        XCTAssertEqual(session.model, "GPT-5.4")
        XCTAssertEqual(session.branch, "feat/codex-rows")
        XCTAssertEqual(session.project, "/tmp/vibeshed")
    }

    func testCodexLegacyHeaderHasBranchOnly() throws {
        let session = try XCTUnwrap(
            codexSessions()["0199bbbb-0000-7000-8000-000000000002"]
        )
        XCTAssertEqual(session.branch, "main")
        XCTAssertNil(session.model)
        XCTAssertNil(session.project)
    }

    // MARK: - Model names

    func testAnthropicModelNames() {
        let cases = [
            "claude-opus-5-5": "Opus 5.5",
            "claude-sonnet-5": "Sonnet 5",
            "claude-haiku-4-5-20251001": "Haiku 4.5",
            "claude-3-5-sonnet-20241022": "Sonnet 3.5",
            "claude-3-opus-20240229": "Opus 3",
            "claude-opus-4-6[1m]": "Opus 4.6",
            "us.anthropic.claude-sonnet-4-5-20250929-v1:0": "Sonnet 4.5",
            "claude-sonnet-4-5@20250929": "Sonnet 4.5",
            // Not a family-plus-version id: shown as recorded.
            "claude-3-5-sonnet-latest": "claude-3-5-sonnet-latest",
            "opus": "opus",
        ]
        for (id, expected) in cases {
            XCTAssertEqual(AnthropicModelName.displayName(for: id), expected, id)
        }
    }

    func testOpenAIModelNames() {
        let cases = [
            "gpt-5.4": "GPT-5.4",
            "gpt-5.3-codex": "GPT-5.3-Codex",
            "gpt-5.1-codex-max": "GPT-5.1-Codex-Max",
            "o3": "o3",
            "codex-auto-review": "codex-auto-review",
            "gpt-oss": "gpt-oss",
        ]
        for (id, expected) in cases {
            XCTAssertEqual(OpenAIModelName.displayName(for: id), expected, id)
        }
    }

    // MARK: - Picker rows

    func testSessionActionCarriesModelAndBranchToPreview() {
        let action = sessionAction(model: "Opus 5.5", branch: "feat/preview-rows")
        XCTAssertEqual(action.modelName, "Opus 5.5")
        XCTAssertEqual(action.branch, "feat/preview-rows")
        XCTAssertTrue(
            action.subtitle.hasPrefix("Claude Code · /tmp/vibeshed · Opus 5.5 · "),
            action.subtitle
        )
        XCTAssertTrue(action.keywords.contains("feat/preview-rows"))
    }

    func testSessionActionWithoutMetadataOmitsRows() {
        let action = sessionAction(model: nil, branch: nil)
        XCTAssertNil(action.modelName)
        XCTAssertNil(action.branch)
        XCTAssertTrue(
            action.subtitle.hasPrefix("Claude Code · /tmp/vibeshed · "),
            action.subtitle
        )
        XCTAssertEqual(action.subtitle.components(separatedBy: " · ").count, 3)
    }

    private func sessionAction(model: String?, branch: String?) -> AIAction {
        let session = AISession(
            sessionID: "11111111-1111-4111-8111-111111111111",
            cliSessionID: "11111111-1111-4111-8111-111111111111",
            source: AnthropicProvider.claudeCode,
            title: "add branch and model to the preview",
            project: "/tmp/vibeshed",
            model: model,
            branch: branch,
            timestamp: Date()
        )
        return AIAction.forSession(
            session,
            module: AnthropicProvider.identity,
            namePrefix: "session",
            relevanceScore: 1
        ) {}
    }
}
