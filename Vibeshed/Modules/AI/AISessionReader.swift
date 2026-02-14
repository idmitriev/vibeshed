import Foundation

// MARK: - Data Types

enum AIProvider: String, Sendable {
    case claudeCode
    case claudeDesktop
    case codex
}

struct AISession: Sendable {
    let sessionID: String
    let provider: AIProvider
    let title: String
    let lastPrompt: String?
    let project: String?
    let model: String?
    let timestamp: Date
    let isArchived: Bool
}

// MARK: - Reader

enum AISessionReader {

    static func readAllSessions(
        providers: [String],
        maxResults: Int
    ) -> [AISession] {
        var sessions: [AISession] = []

        let desktopMeta = providers.contains("claudeDesktop")
            ? readClaudeDesktopMetadata() : []

        let titleLookup = buildTitleLookup(desktopMeta)

        if providers.contains("claudeCode") {
            sessions.append(contentsOf: readClaudeCodeSessions(
                maxResults: maxResults,
                titleLookup: titleLookup
            ))
        }

        let claudeCodeIDs = Set(sessions.map(\.sessionID))
        if providers.contains("claudeDesktop") {
            sessions.append(contentsOf: readClaudeDesktopSessions(
                from: desktopMeta,
                maxResults: maxResults,
                excludeCliIDs: claudeCodeIDs
            ))
        }

        if providers.contains("codex") {
            sessions.append(contentsOf: readCodexSessions(
                maxResults: maxResults
            ))
        }

        sessions.sort { $0.timestamp > $1.timestamp }
        return Array(sessions.prefix(maxResults))
    }

    // MARK: - Claude Code

    private static func readClaudeCodeSessions(
        maxResults: Int,
        titleLookup: [String: String]
    ) -> [AISession] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let path = home.appendingPathComponent(
            ".claude/history.jsonl"
        ).path
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8)
        else { return [] }

        let entries = parseClaudeCodeEntries(content)
        let grouped = Dictionary(grouping: entries, by: \.sessionId)
        return buildClaudeCodeSessions(
            grouped: grouped,
            titleLookup: titleLookup,
            maxResults: maxResults
        )
    }

    private static func parseClaudeCodeEntries(
        _ content: String
    ) -> [ClaudeCodeEntry] {
        var entries: [ClaudeCodeEntry] = []
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(
                      with: lineData
                  ) as? [String: Any],
                  let display = json["display"] as? String,
                  let ts = json["timestamp"] as? Double,
                  let sid = json["sessionId"] as? String
            else { continue }
            entries.append(ClaudeCodeEntry(
                display: display,
                timestamp: ts,
                project: json["project"] as? String,
                sessionId: sid
            ))
        }
        return entries
    }

    private static func buildClaudeCodeSessions(
        grouped: [String: [ClaudeCodeEntry]],
        titleLookup: [String: String],
        maxResults: Int
    ) -> [AISession] {
        var sessions: [AISession] = []
        for (sessionId, group) in grouped {
            let sorted = group.sorted { $0.timestamp < $1.timestamp }
            guard let first = sorted.first,
                  let last = sorted.last
            else { continue }

            let title = deriveClaudeCodeTitle(
                sessionId: sessionId,
                firstDisplay: first.display,
                titleLookup: titleLookup
            )
            let lastPrompt = last.display.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            sessions.append(AISession(
                sessionID: sessionId,
                provider: .claudeCode,
                title: title,
                lastPrompt: lastPrompt.isEmpty ? nil : lastPrompt,
                project: first.project,
                model: nil,
                timestamp: Date(
                    timeIntervalSince1970: last.timestamp / 1000
                ),
                isArchived: false
            ))
        }
        sessions.sort { $0.timestamp > $1.timestamp }
        return Array(sessions.prefix(maxResults))
    }

    private static func deriveClaudeCodeTitle(
        sessionId: String,
        firstDisplay: String,
        titleLookup: [String: String]
    ) -> String {
        if let desktopTitle = titleLookup[sessionId] {
            return desktopTitle
        }
        let trimmed = firstDisplay.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if trimmed.isEmpty || trimmed.hasPrefix("/") {
            return "Session \(sessionId.prefix(8))"
        }
        return String(trimmed.prefix(80))
    }

    // MARK: - Claude Desktop

    private static func readClaudeDesktopMetadata()
        -> [DesktopSessionMeta]
    {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Claude/claude-code-sessions"
            )
        guard FileManager.default.fileExists(atPath: base.path) else {
            return []
        }

        let fm = FileManager.default
        var metas: [DesktopSessionMeta] = []

        guard let accounts = try? fm.contentsOfDirectory(
            atPath: base.path
        ) else { return [] }

        for account in accounts {
            let accountDir = base.appendingPathComponent(account)
            metas.append(contentsOf: readAccountSessions(
                fm: fm, accountDir: accountDir
            ))
        }
        return metas
    }

    private static func readAccountSessions(
        fm: FileManager,
        accountDir: URL
    ) -> [DesktopSessionMeta] {
        var isDir: ObjCBool = false
        guard fm.fileExists(
            atPath: accountDir.path, isDirectory: &isDir
        ), isDir.boolValue else { return [] }

        guard let sessionDirs = try? fm.contentsOfDirectory(
            atPath: accountDir.path
        ) else { return [] }

        var metas: [DesktopSessionMeta] = []
        for sessionDir in sessionDirs {
            let sessionPath = accountDir.appendingPathComponent(sessionDir)
            guard fm.fileExists(
                atPath: sessionPath.path, isDirectory: &isDir
            ), isDir.boolValue else { continue }
            metas.append(contentsOf: readSessionFiles(
                fm: fm, sessionPath: sessionPath
            ))
        }
        return metas
    }

    private static func readSessionFiles(
        fm: FileManager,
        sessionPath: URL
    ) -> [DesktopSessionMeta] {
        guard let files = try? fm.contentsOfDirectory(
            atPath: sessionPath.path
        ) else { return [] }

        var metas: [DesktopSessionMeta] = []
        for file in files where file.hasSuffix(".json") {
            let filePath = sessionPath.appendingPathComponent(file)
            if let meta = parseDesktopSessionFile(filePath) {
                metas.append(meta)
            }
        }
        return metas
    }

    private static func parseDesktopSessionFile(
        _ url: URL
    ) -> DesktopSessionMeta? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(
                  with: data
              ) as? [String: Any],
              let sessionId = json["sessionId"] as? String,
              let lastActivity = json["lastActivityAt"] as? Double
        else { return nil }

        return DesktopSessionMeta(
            sessionId: sessionId,
            cliSessionId: json["cliSessionId"] as? String,
            title: json["title"] as? String,
            cwd: json["cwd"] as? String,
            model: json["model"] as? String,
            lastActivityAt: lastActivity,
            isArchived: json["isArchived"] as? Bool ?? false
        )
    }

    private static func readClaudeDesktopSessions(
        from metas: [DesktopSessionMeta],
        maxResults: Int,
        excludeCliIDs: Set<String>
    ) -> [AISession] {
        var sessions: [AISession] = []
        for meta in metas {
            if meta.isArchived { continue }
            if let cliID = meta.cliSessionId,
               excludeCliIDs.contains(cliID) {
                continue
            }
            let title = meta.title
                ?? "Session \(meta.sessionId.prefix(8))"
            sessions.append(AISession(
                sessionID: meta.sessionId,
                provider: .claudeDesktop,
                title: title,
                lastPrompt: nil,
                project: meta.cwd,
                model: meta.model,
                timestamp: Date(
                    timeIntervalSince1970: meta.lastActivityAt / 1000
                ),
                isArchived: false
            ))
        }
        sessions.sort { $0.timestamp > $1.timestamp }
        return Array(sessions.prefix(maxResults))
    }

    private static func buildTitleLookup(
        _ metas: [DesktopSessionMeta]
    ) -> [String: String] {
        var lookup: [String: String] = [:]
        for meta in metas {
            guard let cliID = meta.cliSessionId,
                  let title = meta.title
            else { continue }
            if lookup[cliID] == nil {
                lookup[cliID] = title
            }
        }
        return lookup
    }

    // MARK: - Codex

    private static func readCodexSessions(
        maxResults: Int
    ) -> [AISession] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let codexDir = home.appendingPathComponent(".codex")

        let titles = readCodexThreadTitles(codexDir: codexDir)

        let historyPath = codexDir
            .appendingPathComponent("history.jsonl").path
        guard let data = FileManager.default.contents(
            atPath: historyPath
        ),
              let content = String(data: data, encoding: .utf8)
        else { return [] }

        let entries = parseCodexEntries(content)
        let grouped = Dictionary(grouping: entries, by: \.sessionId)
        return buildCodexSessions(
            grouped: grouped,
            titles: titles,
            maxResults: maxResults
        )
    }

    private static func parseCodexEntries(
        _ content: String
    ) -> [CodexEntry] {
        var entries: [CodexEntry] = []
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(
                      with: lineData
                  ) as? [String: Any],
                  let sid = json["session_id"] as? String,
                  let ts = json["ts"] as? Double,
                  let text = json["text"] as? String
            else { continue }
            entries.append(CodexEntry(
                sessionId: sid, timestamp: ts, text: text
            ))
        }
        return entries
    }

    private static func buildCodexSessions(
        grouped: [String: [CodexEntry]],
        titles: [String: String],
        maxResults: Int
    ) -> [AISession] {
        var sessions: [AISession] = []
        for (sessionId, group) in grouped {
            let sorted = group.sorted { $0.timestamp < $1.timestamp }
            guard let first = sorted.first,
                  let last = sorted.last
            else { continue }

            let title = deriveCodexTitle(
                sessionId: sessionId,
                firstText: first.text,
                titles: titles
            )
            let lastPrompt = last.text.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            sessions.append(AISession(
                sessionID: sessionId,
                provider: .codex,
                title: title,
                lastPrompt: lastPrompt.isEmpty ? nil : lastPrompt,
                project: nil,
                model: nil,
                timestamp: Date(
                    timeIntervalSince1970: last.timestamp
                ),
                isArchived: false
            ))
        }
        sessions.sort { $0.timestamp > $1.timestamp }
        return Array(sessions.prefix(maxResults))
    }

    private static func deriveCodexTitle(
        sessionId: String,
        firstText: String,
        titles: [String: String]
    ) -> String {
        if let threadTitle = titles[sessionId] {
            return threadTitle
        }
        let trimmed = firstText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if trimmed.isEmpty {
            return "Session \(sessionId.prefix(8))"
        }
        return String(trimmed.prefix(80))
    }

    private static func readCodexThreadTitles(
        codexDir: URL
    ) -> [String: String] {
        let statePath = codexDir
            .appendingPathComponent(".codex-global-state.json")
        guard let data = try? Data(contentsOf: statePath),
              let json = try? JSONSerialization.jsonObject(
                  with: data
              ) as? [String: Any],
              let threadTitles = json["thread-titles"]
                  as? [String: Any],
              let titles = threadTitles["titles"] as? [String: String]
        else { return [:] }
        return titles
    }
}

// MARK: - Internal Types

private struct ClaudeCodeEntry {
    let display: String
    let timestamp: Double
    let project: String?
    let sessionId: String
}

private struct DesktopSessionMeta {
    let sessionId: String
    let cliSessionId: String?
    let title: String?
    let cwd: String?
    let model: String?
    let lastActivityAt: Double
    let isArchived: Bool
}

private struct CodexEntry {
    let sessionId: String
    let timestamp: Double
    let text: String
}
