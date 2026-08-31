import Foundation
@testable import Vibeshed
import XCTest

/// Covers the vendor split: shared config validation, deeplink construction and the
/// identifier shapes each vendor's reopen path depends on.
final class AISessionsModuleTests: XCTestCase {
    // MARK: - Config decoding

    /// A config section predating a newly added field must still decode. Synthesized
    /// Decodable would throw `keyNotFound`, which `ModuleConfigDecoder` swallows by
    /// discarding the user's whole section back to defaults.
    func testAnthropicConfigDecodesFromPartialYAML() throws {
        let json = Data(#"{"maxResults": 5}"#.utf8)
        let config = try JSONDecoder().decode(AnthropicConfig.self, from: json)
        XCTAssertEqual(config.maxResults, 5)
        XCTAssertEqual(config.sources, ["claudeCode", "claudeDesktop"])
        XCTAssertTrue(config.showLaunchers)
        XCTAssertEqual(config.resumeIn, .terminal)
    }

    func testOpenAIConfigDecodesFromEmptySection() throws {
        let json = Data("{}".utf8)
        let config = try JSONDecoder().decode(OpenAIConfig.self, from: json)
        XCTAssertEqual(config.maxResults, 20)
        XCTAssertEqual(config.sources, ["codex"])
        XCTAssertFalse(config.newSessionInTerminal)
    }

    // MARK: - Validation

    func testRejectsUnknownSource() {
        var config = AnthropicConfig()
        config.sources = ["claudeCode", "gemini"]
        let result = AnthropicProvider.validate(config)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(
            result.errors.contains { $0.contains("gemini") },
            "Expected the invalid source to be named: \(result.errors)"
        )
    }

    func testRejectsOutOfRangeMaxResults() {
        var config = OpenAIConfig()
        config.maxResults = 0
        XCTAssertFalse(OpenAIProvider.validate(config).isValid)
    }

    func testAcceptsDefaults() {
        XCTAssertTrue(AnthropicProvider.validate(AnthropicConfig()).isValid)
        XCTAssertTrue(OpenAIProvider.validate(OpenAIConfig()).isValid)
    }

    func testRejectsUnknownTerminalApp() {
        var config = AnthropicConfig()
        config.terminalApp = "kitty"
        XCTAssertFalse(AnthropicProvider.validate(config).isValid)
    }

    // MARK: - Anthropic deeplinks

    func testResumeRequiresPlainUUID() {
        let uuid = "9fef40c3-cf00-4b2b-9909-07009df7ea0e"
        XCTAssertEqual(
            AnthropicDeeplink.resumeCLISession(uuid),
            "claude://resume?session=\(uuid)"
        )
        // Desktop-side ids are not accepted by the resume handler.
        XCTAssertNil(AnthropicDeeplink.resumeCLISession("local_\(uuid)"))
        XCTAssertNil(AnthropicDeeplink.resumeCLISession("not-a-uuid"))
    }

    func testSessionIDShapes() {
        let uuid = "9fef40c3-cf00-4b2b-9909-07009df7ea0e"
        XCTAssertTrue(AnthropicDeeplink.isCLISessionID(uuid))
        XCTAssertFalse(AnthropicDeeplink.isDesktopSessionID(uuid))
        XCTAssertTrue(AnthropicDeeplink.isDesktopSessionID("local_\(uuid)"))
        XCTAssertFalse(AnthropicDeeplink.isDesktopSessionID("local_nope"))
    }

    func testContinueAcceptsLastSentinel() {
        XCTAssertEqual(
            AnthropicDeeplink.continueLast,
            "claude://code/continue?session=last&source=vibeshed"
        )
    }

    func testNewCodeSessionOmitsAbsentParameters() {
        XCTAssertEqual(
            AnthropicDeeplink.newCodeSession(prompt: nil, folder: nil),
            "claude://code/new?source=vibeshed"
        )
    }

    func testNewCodeSessionEncodesPromptAndFolder() throws {
        let raw = try XCTUnwrap(
            AnthropicDeeplink.newCodeSession(
                prompt: "fix the bug & ship", folder: "/tmp/my project"
            )
        )
        let components = try XCTUnwrap(URLComponents(string: raw))
        let items = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? [])
                .map { ($0.name, $0.value) }
        )
        XCTAssertEqual(items["q"], "fix the bug & ship")
        XCTAssertEqual(items["folder"], "/tmp/my project")
        XCTAssertEqual(components.path, "/new")
    }

    // MARK: - OpenAI deeplinks

    func testCodexThreadURL() {
        XCTAssertEqual(
            OpenAIDeeplink.thread("01a03345-815f-77f2-a719-293b09872aaf"),
            "codex://threads/01a03345-815f-77f2-a719-293b09872aaf"
        )
    }

    // MARK: - Session matching

    func testSessionMatchesTitleProjectAndPrompt() {
        let session = AISession(
            sessionID: "id",
            source: OpenAIProvider.codex,
            title: "Refactor the picker",
            lastPrompt: "split AI module",
            project: "/Users/me/Projects/vibeshed",
            timestamp: Date()
        )
        XCTAssertTrue(session.matches(lowercasedQuery: "picker"))
        XCTAssertTrue(session.matches(lowercasedQuery: "vibeshed"))
        XCTAssertTrue(session.matches(lowercasedQuery: "split ai"))
        XCTAssertFalse(session.matches(lowercasedQuery: "spotify"))
    }

    // MARK: - Shared helpers

    func testShellQuoteEscapesEmbeddedQuote() {
        XCTAssertEqual(AILaunch.shellQuote("it's"), #"'it'\''s'"#)
    }

    func testTrimmedTreatsBlankAsAbsent() {
        XCTAssertNil(AILaunch.trimmed("   "))
        XCTAssertNil(AILaunch.trimmed(nil))
        XCTAssertEqual(AILaunch.trimmed("  hi  "), "hi")
    }

    func testURLDropsNilQueryValues() {
        XCTAssertEqual(
            AILaunch.url("https://example.com/", query: ["q": nil]),
            "https://example.com/"
        )
    }
}
