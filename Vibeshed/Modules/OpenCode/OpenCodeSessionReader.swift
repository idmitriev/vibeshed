import Foundation
import OSLog
import SQLite3

private let log = Log.module("opencode")

/// Reads OpenCode session history from its SQLite database.
///
/// The CLI and the desktop app share `opencode.db`. Since OpenCode's v1→v2 migration,
/// sessions live in `session_v2`; the old `session` table stays behind but stops being
/// updated, so it's only read when `session_v2` is missing. OpenCode migrates its schema
/// every few weeks, so only the core columns are required and the rest are selected
/// when present.
enum OpenCodeSessionReader {
    /// `$XDG_DATA_HOME/opencode/opencode.db`, honouring `OPENCODE_DB` like the CLI.
    static var defaultDatabasePath: String {
        let environment = ProcessInfo.processInfo.environment
        if let path = environment["OPENCODE_DB"], !path.isEmpty, path != ":memory:" {
            return path
        }
        let dataHome = environment["XDG_DATA_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            ?? NSHomeDirectory() + "/.local/share"
        return dataHome + "/opencode/opencode.db"
    }

    /// The newest top-level sessions, skipping subagent children and archived ones.
    static func readSessions(
        limit: Int,
        databasePath: String = defaultDatabasePath
    ) -> [AISession] {
        guard FileManager.default.fileExists(atPath: databasePath) else {
            log.debug("OpenCode database not found")
            return []
        }
        guard let db = open(databasePath) else { return [] }
        defer { sqlite3_close(db) }

        guard let sql = sessionQuery(in: db) else {
            log.error("OpenCode database has no readable session table")
            return []
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            log.error("OpenCode session query failed: \(String(cString: sqlite3_errmsg(db)), privacy: .public)")
            return []
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(clamping: limit))

        var sessions: [AISession] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let session = session(from: stmt) {
                sessions.append(session)
            }
        }
        log.debug("OpenCode sessions found: \(sessions.count, privacy: .public)")
        return sessions
    }

    // MARK: - Database

    /// Opens read-only without `immutable`, so the query still sees sessions sitting in
    /// the write-ahead log that OpenCode hasn't checkpointed yet.
    private static func open(_ path: String) -> OpaquePointer? {
        let uri = URL(fileURLWithPath: path).absoluteString + "?mode=ro"
        var db: OpaquePointer?
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            log.error("Cannot open OpenCode database at \(path, privacy: .public)")
            sqlite3_close(db)
            return nil
        }
        sqlite3_busy_timeout(db, 250)
        return db
    }

    /// Selects id, title, directory, model and update time, newest first, with `?1`
    /// as the row limit. Nil when neither session table has the core columns.
    private static func sessionQuery(in db: OpaquePointer) -> String? {
        let required: Set = ["id", "title", "directory", "time_updated"]
        for table in ["session_v2", "session"] {
            let columns = columnNames(of: table, in: db)
            guard required.isSubset(of: columns) else { continue }
            var filters: [String] = []
            if columns.contains("parent_id") {
                filters.append("parent_id IS NULL")
            }
            if columns.contains("time_archived") {
                filters.append("time_archived IS NULL")
            }
            let model = columns.contains("model") ? "model" : "NULL"
            let whereClause = filters.isEmpty ? "" : "WHERE \(filters.joined(separator: " AND ")) "
            return """
            SELECT id, title, directory, \(model), time_updated FROM \(table) \
            \(whereClause)ORDER BY time_updated DESC LIMIT ?1
            """
        }
        return nil
    }

    private static func columnNames(of table: String, in db: OpaquePointer) -> Set<String> {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &stmt, nil) == SQLITE_OK,
              let stmt
        else { return [] }
        defer { sqlite3_finalize(stmt) }
        var names: Set<String> = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = sqlite3_column_text(stmt, 1) {
                names.insert(String(cString: name))
            }
        }
        return names
    }

    // MARK: - Rows

    private static func session(from stmt: OpaquePointer) -> AISession? {
        guard let id = text(stmt, 0), !id.isEmpty else { return nil }
        let updatedMillis = sqlite3_column_int64(stmt, 4)
        return AISession(
            sessionID: id,
            source: OpenCodeProvider.opencode,
            title: displayTitle(text(stmt, 1)) ?? "Session \(id.suffix(8))",
            project: text(stmt, 2).flatMap { $0.isEmpty ? nil : $0 },
            model: text(stmt, 3).flatMap(OpenCodeModelName.displayName(fromStored:)),
            timestamp: Date(timeIntervalSince1970: Double(updatedMillis) / 1000)
        )
    }

    private static func text(_ stmt: OpaquePointer, _ column: Int32) -> String? {
        sqlite3_column_text(stmt, column).map { String(cString: $0) }
    }

    /// OpenCode titles a session "New session - <ISO date>" until it summarizes the
    /// first exchange. The row already shows when it ran, so the date is dropped.
    static func displayTitle(_ stored: String?) -> String? {
        guard let title = stored?.asSessionTitle() else { return nil }
        let prefix = "New session - "
        guard title.hasPrefix(prefix) else { return title }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = String(title.dropFirst(prefix.count))
        return formatter.date(from: date) != nil ? "New session" : title
    }
}
