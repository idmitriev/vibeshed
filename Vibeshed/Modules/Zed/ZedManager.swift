import AppKit
import Foundation
import OSLog
import SQLite3

private let log = Log.module("zed")

struct ZedWorkspace: Sendable {
    let name: String
    let path: String
    let isRemote: Bool
    let remoteHost: String?
    let lastOpened: Date
    let isOpen: Bool
}

enum ZedManager {
    static func discoverWorkspaces(
        maxResults: Int,
        showRemote: Bool
    ) -> [ZedWorkspace] {
        let dbPath = dbPath()
        guard let dbPath, FileManager.default.fileExists(atPath: dbPath) else {
            log.debug("No Zed database found")
            return []
        }

        let openTitles = collectOpenWindowTitles()
        var workspaces = queryWorkspaces(
            dbPath: dbPath,
            showRemote: showRemote
        )

        var seen = Set<String>()
        workspaces = workspaces.filter { seen.insert($0.path).inserted }

        workspaces = workspaces.map { ws in
            let isOpen = openTitles.contains { $0.contains(ws.name) }
            guard isOpen else { return ws }
            return ZedWorkspace(
                name: ws.name,
                path: ws.path,
                isRemote: ws.isRemote,
                remoteHost: ws.remoteHost,
                lastOpened: ws.lastOpened,
                isOpen: true
            )
        }

        return Array(workspaces.prefix(maxResults))
    }

    static func openWorkspace(path: String, zedPath: String?) {
        guard let cli = resolveZedCLI(customPath: zedPath) else {
            log.debug("No zed CLI found, falling back to NSWorkspace.open")
            let url = URL(fileURLWithPath: path)
            DispatchQueue.main.async {
                NSWorkspace.shared.open(
                    [url],
                    withApplicationAt: URL(
                        fileURLWithPath: "/Applications/Zed.app"
                    ),
                    configuration: .init()
                )
            }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: cli)
            process.arguments = [path]
            do {
                try process.run()
            } catch {
                log.warning(
                    "openWorkspace: zed CLI failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    // MARK: - Private

    private static func dbPath() -> String? {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Zed/db/0-stable")
        let path = appSupport.appendingPathComponent("db.sqlite").path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    private static func resolveZedCLI(customPath: String?) -> String? {
        if let custom = customPath {
            if FileManager.default.isExecutableFile(atPath: custom) {
                return custom
            }
            log.warning("Custom zed CLI path not executable: \(custom, privacy: .public)")
            return nil
        }
        let candidates = [
            "/opt/homebrew/bin/zed",
            "/usr/local/bin/zed",
            "/Applications/Zed.app/Contents/MacOS/cli",
        ]
        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    private static func collectOpenWindowTitles() -> Set<String> {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[CFString: Any]] else {
            return []
        }

        var titles = Set<String>()
        for window in windowList {
            guard let ownerName = window[kCGWindowOwnerName] as? String,
                  ownerName == "Zed",
                  let title = window[kCGWindowName] as? String,
                  !title.isEmpty
            else { continue }
            titles.insert(title)
        }
        return titles
    }

    private static func queryWorkspaces(
        dbPath: String,
        showRemote: Bool
    ) -> [ZedWorkspace] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(
            dbPath, &db, SQLITE_OPEN_READONLY, nil
        ) == SQLITE_OK else {
            log.error("SQLite open failed for \(dbPath, privacy: .public)")
            return []
        }
        defer { sqlite3_close(db) }

        let sql: String
        if showRemote {
            sql = """
                SELECT w.paths, w.timestamp, r.kind, r.host, r.user \
                FROM workspaces w \
                LEFT JOIN remote_connections r ON w.remote_connection_id = r.id \
                WHERE w.paths IS NOT NULL AND w.paths != '' \
                ORDER BY w.timestamp DESC
                """
        } else {
            sql = """
                SELECT w.paths, w.timestamp, NULL, NULL, NULL \
                FROM workspaces w \
                WHERE w.paths IS NOT NULL AND w.paths != '' \
                AND w.remote_connection_id IS NULL \
                ORDER BY w.timestamp DESC
                """
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            log.error("SQLite prepare failed")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        var workspaces: [ZedWorkspace] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let pathsPtr = sqlite3_column_text(stmt, 0) else { continue }
            let paths = String(cString: pathsPtr)
            guard !paths.isEmpty else { continue }

            let timestampStr = sqlite3_column_text(stmt, 1)
                .map { String(cString: $0) }
            let lastOpened = timestampStr.flatMap {
                parseTimestamp($0, formatter: formatter, fallback: fallbackFormatter)
            } ?? .distantPast

            let kind = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            let host = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
            let user = sqlite3_column_text(stmt, 4).map { String(cString: $0) }

            let isRemote = kind != nil

            let remoteHost: String?
            if let host {
                remoteHost = user != nil ? "\(user!)@\(host)" : host
            } else {
                remoteHost = nil
            }

            let name = projectName(from: paths)

            workspaces.append(ZedWorkspace(
                name: name,
                path: paths,
                isRemote: isRemote,
                remoteHost: remoteHost,
                lastOpened: lastOpened,
                isOpen: false
            ))
        }

        return workspaces
    }

    private static func parseTimestamp(
        _ string: String,
        formatter: ISO8601DateFormatter,
        fallback: ISO8601DateFormatter
    ) -> Date? {
        if let date = formatter.date(from: string) { return date }
        if let date = fallback.date(from: string) { return date }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        df.timeZone = TimeZone(identifier: "UTC")
        return df.date(from: string)
    }

    private static func projectName(from path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}
