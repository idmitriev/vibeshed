import AppKit
import Foundation
import OSLog
import SQLite3

private let log = Log.module("vscode")

// MARK: - Data Types

struct VSCodeProject: Sendable {
    let name: String
    let path: String
    let isRemote: Bool
    let remoteLabel: String?
    let variant: String
}

// MARK: - Manager

enum VSCodeManager {
    /// Known VSCode variant directories under ~/Library/Application Support/
    static let defaultVariants: [(name: String, dir: String)] = [
        ("VS Code", "Code"),
        ("VS Code Insiders", "Code - Insiders"),
        ("VSCodium", "VSCodium"),
        ("Cursor", "Cursor"),
        ("Windsurf", "Windsurf"),
    ]

    static func discoverProjects(
        maxResults: Int,
        showFiles: Bool,
        showRemote: Bool,
        extraVariants: [String: String]?
    ) -> [VSCodeProject] {
        var allVariants = defaultVariants
        if let extra = extraVariants {
            for (name, dir) in extra {
                if !allVariants.contains(where: { $0.dir == dir }) {
                    allVariants.append((name, dir))
                }
            }
        }

        var projects: [VSCodeProject] = []
        for variant in allVariants {
            let entries = readRecentEntries(
                variant: variant.name,
                dir: variant.dir,
                showFiles: showFiles,
                showRemote: showRemote
            )
            projects.append(contentsOf: entries)
        }

        // Deduplicate by path, keeping first occurrence (most recent)
        var seen = Set<String>()
        projects = projects.filter { seen.insert($0.path).inserted }

        return Array(projects.prefix(maxResults))
    }

    static func resolveCodeCLI(customPath: String?) -> String? {
        if let custom = customPath {
            if FileManager.default.isExecutableFile(atPath: custom) {
                return custom
            }
            log.warning("Custom code CLI path not executable: \(custom)")
            return nil
        }
        let candidates = [
            "/opt/homebrew/bin/code",
            "/usr/local/bin/code",
            "/Applications/Visual Studio Code.app"
                + "/Contents/Resources/app/bin/code",
        ]
        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    static func openProject(path: String, codePath: String?) {
        guard let cli = resolveCodeCLI(customPath: codePath) else {
            log.debug("No code CLI found, falling back to NSWorkspace.open")
            let url = URL(fileURLWithPath: path)
            DispatchQueue.main.async {
                NSWorkspace.shared.open(
                    [url],
                    withApplicationAt: URL(
                        fileURLWithPath:
                            "/Applications/Visual Studio Code.app"
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
                log.warning("openProject: code CLI failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private

    private static func readRecentEntries(
        variant: String,
        dir: String,
        showFiles: Bool,
        showRemote: Bool
    ) -> [VSCodeProject] {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(dir)
        let dbPath = appSupport
            .appendingPathComponent("User/globalStorage/state.vscdb")
            .path

        guard FileManager.default.fileExists(atPath: dbPath) else {
            log.debug("No state.vscdb for \(variant) at \(dbPath)")
            return []
        }

        return queryStateDB(
            dbPath: dbPath,
            variant: variant,
            showFiles: showFiles,
            showRemote: showRemote
        )
    }

    private static func queryStateDB(
        dbPath: String,
        variant: String,
        showFiles: Bool,
        showRemote: Bool
    ) -> [VSCodeProject] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(
            dbPath, &db, SQLITE_OPEN_READONLY, nil
        ) == SQLITE_OK else {
            log.error("SQLite open failed for \(dbPath)")
            return []
        }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT value FROM ItemTable \
            WHERE key = 'history.recentlyOpenedPathsList'
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            log.error("SQLite prepare failed for \(variant)")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return []
        }

        guard let textPtr = sqlite3_column_text(stmt, 0) else {
            return []
        }
        let jsonString = String(cString: textPtr)

        return parseRecentlyOpened(
            jsonString,
            variant: variant,
            showFiles: showFiles,
            showRemote: showRemote
        )
    }

    private static func parseRecentlyOpened(
        _ jsonString: String,
        variant: String,
        showFiles: Bool,
        showRemote: Bool
    ) -> [VSCodeProject] {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data)
                  as? [String: Any],
              let entries = json["entries"] as? [[String: Any]]
        else {
            log.warning("Failed to parse recentlyOpenedPathsList JSON for \(variant)")
            return []
        }

        var projects: [VSCodeProject] = []
        for entry in entries {
            if let project = parseEntry(
                entry,
                variant: variant,
                showFiles: showFiles,
                showRemote: showRemote
            ) {
                projects.append(project)
            }
        }
        return projects
    }

    private static func parseEntry(
        _ entry: [String: Any],
        variant: String,
        showFiles: Bool,
        showRemote: Bool
    ) -> VSCodeProject? {
        if let folderUri = entry["folderUri"] as? String {
            return parseFolderEntry(
                folderUri: folderUri,
                label: entry["label"] as? String,
                remoteAuthority: entry["remoteAuthority"] as? String,
                variant: variant,
                showRemote: showRemote
            )
        }
        if showFiles, let fileUri = entry["fileUri"] as? String {
            return parseFileEntry(
                fileUri: fileUri,
                variant: variant,
                showRemote: showRemote
            )
        }
        return nil
    }

    private static func parseFolderEntry(
        folderUri: String,
        label: String?,
        remoteAuthority: String?,
        variant: String,
        showRemote: Bool
    ) -> VSCodeProject? {
        let isRemote = remoteAuthority != nil
        if isRemote, !showRemote { return nil }

        let path: String
        if folderUri.hasPrefix("file://") {
            path = fileURIToPath(folderUri)
        } else if isRemote {
            path = folderUri
        } else {
            return nil
        }

        let name = label ?? projectName(from: path)
        return VSCodeProject(
            name: name,
            path: path,
            isRemote: isRemote,
            remoteLabel: label,
            variant: variant
        )
    }

    private static func parseFileEntry(
        fileUri: String,
        variant: String,
        showRemote: Bool
    ) -> VSCodeProject? {
        guard fileUri.hasPrefix("file://") else {
            if showRemote { return nil }
            return nil
        }
        let path = fileURIToPath(fileUri)
        let name = URL(fileURLWithPath: path).lastPathComponent
        return VSCodeProject(
            name: name,
            path: path,
            isRemote: false,
            remoteLabel: nil,
            variant: variant
        )
    }

    private static func fileURIToPath(_ uri: String) -> String {
        guard let url = URL(string: uri) else {
            let stripped = String(uri.dropFirst("file://".count))
            return stripped.removingPercentEncoding ?? stripped
        }
        return url.path
    }

    private static func projectName(from path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}
