import Foundation
import SQLite3
@testable import Vibeshed
import XCTest

/// OpenCode sessions read from scratch copies of `opencode.db`, built with the columns
/// the reader uses from the real `session_v2` and legacy `session` tables.
final class OpenCodeSessionReaderTests: XCTestCase {
    private static let sessionV2 = """
    CREATE TABLE session_v2 (
        id TEXT PRIMARY KEY, parent_id TEXT, directory TEXT NOT NULL, title TEXT,
        model TEXT, time_updated INTEGER NOT NULL, time_archived INTEGER
    )
    """

    private static let kimi = #"{"id":"kimi-k3","providerID":"opencode","variant":"max"}"#
    private static let opus = #"{"id":"claude-opus-5-5","providerID":"anthropic"}"#

    // MARK: - Listing

    func testListsNewestTopLevelSessionsFirst() throws {
        let path = try makeDatabase([
            Self.sessionV2,
            insert("ses_a", title: "Fix the focus border", model: Self.kimi, updated: 3000),
            insert("ses_child", title: "Map tests (@explore subagent)", updated: 4000, parent: "ses_a"),
            insert("ses_archived", title: "Old work", updated: 5000, archived: 5001),
            insert("ses_d", title: "New session - 2026-07-10T11:59:57.846Z", updated: 1000),
            insert("ses_e", title: "Wallpaper preview", model: Self.opus, updated: 2000),
        ])
        let sessions = OpenCodeSessionReader.readSessions(limit: 10, databasePath: path)

        XCTAssertEqual(sessions.map(\.sessionID), ["ses_a", "ses_e", "ses_d"])
        XCTAssertEqual(sessions.map(\.title), ["Fix the focus border", "Wallpaper preview", "New session"])
        XCTAssertEqual(sessions.map(\.model), ["kimi-k3", "Opus 5.5", nil])
        XCTAssertEqual(sessions[0].project, "/tmp/project")
        XCTAssertEqual(sessions[0].source, OpenCodeProvider.opencode)
        XCTAssertEqual(sessions[0].timestamp, Date(timeIntervalSince1970: 3))
        XCTAssertNil(sessions[0].branch)
    }

    func testStopsAtTheLimit() throws {
        let path = try makeDatabase([
            Self.sessionV2,
            insert("ses_1", title: "One", updated: 1000),
            insert("ses_2", title: "Two", updated: 2000),
            insert("ses_3", title: "Three", updated: 3000),
        ])
        let sessions = OpenCodeSessionReader.readSessions(limit: 2, databasePath: path)
        XCTAssertEqual(sessions.map(\.sessionID), ["ses_3", "ses_2"])
    }

    /// The v1 table outlives the v2 migration but stops being updated.
    func testPrefersSessionV2OverTheStaleV1Table() throws {
        let path = try makeDatabase([
            Self.sessionV2.replacingOccurrences(of: "session_v2", with: "session"),
            Self.sessionV2,
            insert("ses_a", title: "Stale title", updated: 1000, table: "session"),
            insert("ses_a", title: "Current title", updated: 2000),
        ])
        let sessions = OpenCodeSessionReader.readSessions(limit: 10, databasePath: path)
        XCTAssertEqual(sessions.map(\.title), ["Current title"])
    }

    /// Databases from before `session_v2`, and before the model, parent and archive
    /// columns existed, still list their sessions.
    func testReadsTheLegacyTableWithOnlyCoreColumns() throws {
        let path = try makeDatabase([
            """
            CREATE TABLE session (
                id TEXT PRIMARY KEY, directory TEXT NOT NULL, title TEXT NOT NULL,
                time_updated INTEGER NOT NULL
            )
            """,
            "INSERT INTO session VALUES ('ses_old', '/tmp/old', 'Lint errors fix', 1000)",
        ])
        let sessions = OpenCodeSessionReader.readSessions(limit: 10, databasePath: path)
        XCTAssertEqual(sessions.map(\.sessionID), ["ses_old"])
        XCTAssertEqual(sessions.first?.project, "/tmp/old")
        XCTAssertNil(sessions.first?.model)
    }

    /// OpenCode runs in WAL mode. A session it just wrote may still sit in the log,
    /// not yet checkpointed, while OpenCode holds the database open.
    func testSeesSessionsStillInTheWriteAheadLog() throws {
        let path = try makeDatabase([Self.sessionV2])
        let writer = try open(path)
        defer { sqlite3_close(writer) }
        try exec(writer, "PRAGMA journal_mode=WAL")
        try exec(writer, "PRAGMA wal_autocheckpoint=0")
        try exec(writer, insert("ses_new", title: "Just started", updated: 1000))
        XCTAssertTrue(FileManager.default.fileExists(atPath: path + "-wal"))

        let sessions = OpenCodeSessionReader.readSessions(limit: 10, databasePath: path)
        XCTAssertEqual(sessions.map(\.sessionID), ["ses_new"])
    }

    func testMissingDatabaseListsNothing() {
        let sessions = OpenCodeSessionReader.readSessions(
            limit: 10, databasePath: "/nonexistent/opencode.db"
        )
        XCTAssertEqual(sessions.count, 0)
    }

    func testDatabaseWithoutSessionTablesListsNothing() throws {
        let path = try makeDatabase(["CREATE TABLE project (id TEXT PRIMARY KEY)"])
        XCTAssertEqual(OpenCodeSessionReader.readSessions(limit: 10, databasePath: path).count, 0)
    }

    // MARK: - Titles and models

    func testKeepsTitlesThatOnlyLookDefault() {
        XCTAssertEqual(OpenCodeSessionReader.displayTitle("New session - auth refactor"), "New session - auth refactor")
        XCTAssertNil(OpenCodeSessionReader.displayTitle("   "))
    }

    func testModelDisplayNames() {
        XCTAssertEqual(OpenCodeModelName.displayName(fromStored: Self.opus), "Opus 5.5")
        XCTAssertEqual(
            OpenCodeModelName.displayName(fromStored: #"{"id":"gpt-5.6-sol","providerID":"openai"}"#),
            "GPT-5.6-Sol"
        )
        let routed = #"{"id":"anthropic/claude-sonnet-4-5","providerID":"openrouter"}"#
        XCTAssertEqual(OpenCodeModelName.displayName(fromStored: routed), "Sonnet 4.5")
        XCTAssertEqual(OpenCodeModelName.displayName(fromStored: "openai/gpt-5.4"), "GPT-5.4")
        XCTAssertEqual(OpenCodeModelName.displayName(fromStored: "kimi-k3"), "kimi-k3")
        XCTAssertNil(OpenCodeModelName.displayName(fromStored: "{not json"))
        XCTAssertNil(OpenCodeModelName.displayName(fromStored: ""))
    }

    // MARK: - Provider

    func testResumeCommandQuotesTheSessionID() {
        XCTAssertEqual(
            OpenCodeProvider.resumeCommand(cli: "/opt/homebrew/bin/opencode", sessionID: "ses_024c56da5ffe"),
            "/opt/homebrew/bin/opencode --session 'ses_024c56da5ffe'"
        )
    }

    func testConfigDecodesFromEmptySection() throws {
        let config = try JSONDecoder().decode(OpenCodeConfig.self, from: Data("{}".utf8))
        XCTAssertEqual(config, OpenCodeConfig())
        XCTAssertEqual(config.sources, ["opencode"])
        XCTAssertTrue(OpenCodeProvider.validate(config).isValid)
    }

    func testRejectsUnknownTerminalAppAndSource() {
        var config = OpenCodeConfig()
        config.terminalApp = "kitty"
        config.sources = ["opencode", "pi"]
        XCTAssertEqual(OpenCodeProvider.validate(config).errors.count, 2)
    }

    // MARK: - Helpers

    private func insert(
        _ id: String,
        title: String,
        model: String? = nil,
        updated: Int,
        parent: String? = nil,
        archived: Int? = nil,
        table: String = "session_v2"
    ) -> String {
        let values = [
            "'\(id)'", parent.map { "'\($0)'" } ?? "NULL", "'/tmp/project'", "'\(title)'",
            model.map { "'\($0)'" } ?? "NULL", "\(updated)", archived.map(String.init) ?? "NULL",
        ]
        return "INSERT INTO \(table) VALUES (\(values.joined(separator: ", ")))"
    }

    /// A fresh database file in its own temporary directory, removed after the test.
    private func makeDatabase(_ statements: [String]) throws -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencode-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("opencode.db").path
        let db = try open(path)
        defer { sqlite3_close(db) }
        for sql in statements {
            try exec(db, sql)
        }
        return path
    }

    private func open(_ path: String) throws -> OpaquePointer {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let db else {
            throw SQLiteError(message: "cannot open \(path)")
        }
        return db
    }

    private func exec(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteError(message: "\(String(cString: sqlite3_errmsg(db))): \(sql)")
        }
    }

    private struct SQLiteError: Error {
        let message: String
    }
}
