import AppKit
import Foundation
import OSLog
import SwiftUI

actor AIModule: ModuleConfigurable {
    let id = "ai"
    let displayName = "AI Sessions"
    let iconName = "brain"
    var isEnabled = true

    typealias Config = AIConfig
    static var defaultConfig: Config? { .init() }

    private var config: AIConfig = .init()
    private var context: ModuleContext?
    private var cachedSessions: [AISession] = []
    private var lastCacheTime: Date = .distantPast
    private let cacheTTL: TimeInterval = 5
    private let log = Log.module("ai")

    func initialize(context: ModuleContext) async throws {
        self.context = context
        refreshCache()
        log.info("AI module initialized (\(self.cachedSessions.count, privacy: .public) sessions found)")
    }

    func teardown() async {
        cachedSessions = []
    }

    func configDidUpdate(_ config: AIConfig) async {
        self.config = config
        refreshCache()
        log.debug("Config updated, cache refreshed (\(self.cachedSessions.count, privacy: .public) sessions)")
    }

    static func validate(
        _ config: AIConfig
    ) -> ConfigValidationResult {
        var errors: [String] = []
        if config.maxResults < 1 || config.maxResults > 100 {
            errors.append("maxResults must be between 1 and 100")
        }
        let validProviders: Set<String> = [
            "claudeCode", "claudeDesktop", "codex",
        ]
        for provider in config.providers {
            if !validProviders.contains(provider) {
                let valid = validProviders.sorted().joined(separator: ", ")
                errors.append(
                    "Invalid provider: '\(provider)'. Valid: \(valid)"
                )
            }
        }
        if let path = config.claudePath,
           !path.isEmpty,
           !FileManager.default.fileExists(atPath: path) {
            errors.append("claudePath does not exist: \(path)")
        }
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    func provideActions(
        query: String,
        scoring: ScoringContext
    ) async -> [any Action] {
        refreshCacheIfNeeded()
        let actions = buildActions()

        return actions
    }

    // MARK: - Cache

    private func refreshCacheIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastCacheTime) > cacheTTL else {
            return
        }
        refreshCache()
    }

    private func refreshCache() {
        cachedSessions = AISessionReader.readAllSessions(
            providers: config.providers,
            maxResults: config.maxResults
        )
        lastCacheTime = Date()
    }

    // MARK: - Action Building

    private func actionName(_ id: ActionID) -> String {
        id.actionName
    }

    private func buildActions() -> [AIAction] {
        let enabled = config.enabledActions
        var actions: [AIAction] = []

        actions.append(buildSearchAction())
        actions.append(contentsOf: buildSessionActions())
        actions.append(contentsOf: buildLauncherActions())

        if let enabled {
            return actions.filter { enabled.contains(actionName($0.id)) }
        }
        return actions
    }

    private func buildSearchAction() -> AIAction {
        let config = self.config
        return AIAction(
            id: ActionID(module: "ai", name: "search"),
            title: "Search AI Sessions",
            subtitle: "Search across all AI session history",
            iconName: "magnifyingglass",
            relevanceScore: 0.9,
            keywords: [
                "ai", "search", "session", "claude", "codex",
                "chatgpt", "history",
            ],
            parameters: [
                ActionParameter(
                    id: "query",
                    label: "Search Query",
                    type: .text(placeholder: "Search sessions..."),
                    isRequired: true
                ),
            ],
            aiItemType: .search
        ) { [config] values in
            guard let query = values["query"] as? String,
                  !query.isEmpty
            else {
                return .showResult(
                    title: "Search AI Sessions",
                    body: "Please enter a search query"
                )
            }
            let sessions = AISessionReader.readAllSessions(
                providers: config.providers,
                maxResults: config.maxResults * 3
            )
            let lowered = query.lowercased()
            let matches = sessions.filter {
                $0.title.lowercased().contains(lowered)
                    || ($0.lastPrompt?.lowercased()
                        .contains(lowered) ?? false)
                    || ($0.project?.lowercased()
                        .contains(lowered) ?? false)
            }
            if matches.isEmpty {
                return .showResult(
                    title: "No Results",
                    body: "No sessions matching \"\(query)\""
                )
            }
            let resultActions = Self.buildSearchResults(
                Array(matches.prefix(config.maxResults)),
                config: config
            )
            return .pushActions(resultActions)
        }
    }

    private func buildSessionActions() -> [AIAction] {
        let config = self.config
        return cachedSessions.enumerated().map { index, session in
            let score = max(0.3, 0.95 - Double(index) * 0.02)
            let subtitle = Self.sessionSubtitle(session)
            var kw: [String] = [
                "ai", "session", "chat",
                session.provider.rawValue.lowercased(),
                session.title.lowercased(),
            ]
            if let project = session.project {
                kw.append(
                    project.lowercased()
                        .replacingOccurrences(of: "/", with: " ")
                )
            }
            return AIAction(
                id: ActionID(
                    module: "ai",
                    name: "session.\(Self.stableID(session.sessionID))"
                ),
                title: session.title,
                subtitle: subtitle,
                iconName: Self.iconForProvider(session.provider),
                relevanceScore: score,
                keywords: kw,
                provider: session.provider,
                aiItemType: .session,
                projectPath: session.project,
                modelName: session.model,
                sessionTimestamp: session.timestamp
            ) { [config] _ in
                Self.openSession(session, config: config)
                return .dismiss
            }
        }
    }

    private func buildLauncherActions() -> [AIAction] {
        guard config.showLaunchers else { return [] }
        var actions: [AIAction] = []

        actions.append(AIAction(
            id: ActionID(module: "ai", name: "openChatGPT"),
            title: "Open ChatGPT",
            subtitle: "Open chatgpt.com in browser",
            iconName: "globe",
            relevanceScore: 0.65,
            keywords: ["ai", "chatgpt", "openai", "open", "web"],
            aiItemType: .launcher
        ) { _ in
            Self.openURL("https://chatgpt.com")
            return .dismiss
        })

        return actions
    }

    // MARK: - Search Results

    private static func buildSearchResults(
        _ sessions: [AISession],
        config: AIConfig
    ) -> [AIAction] {
        sessions.enumerated().map { index, session in
            let score = max(0.3, 0.95 - Double(index) * 0.03)
            let subtitle = sessionSubtitle(session)
            return AIAction(
                id: ActionID(
                    module: "ai",
                    name: "result.\(stableID(session.sessionID))"
                ),
                title: session.title,
                subtitle: subtitle,
                iconName: iconForProvider(session.provider),
                relevanceScore: score,
                keywords: [
                    "ai", session.provider.rawValue.lowercased(),
                    session.title.lowercased(),
                ],
                provider: session.provider,
                aiItemType: .session,
                projectPath: session.project,
                modelName: session.model,
                sessionTimestamp: session.timestamp
            ) { [config] _ in
                openSession(session, config: config)
                return .dismiss
            }
        }
    }

    // MARK: - Session Opening

    @Sendable
    private static func openSession(
        _ session: AISession,
        config: AIConfig
    ) {
        switch session.provider {
        case .claudeCode:
            let cli = resolveClaudeCLI(customPath: config.claudePath)
            let command = "\(cli) --resume \(session.sessionID)"
            launchInTerminal(
                command: command,
                cwd: session.project,
                terminalApp: config.terminalApp
            )
        case .claudeDesktop:
            openApp(bundleID: "com.anthropic.claudefordesktop")
        case .codex:
            openApp(bundleID: "com.openai.codex")
        }
    }

    private static func resolveClaudeCLI(
        customPath: String?
    ) -> String {
        if let custom = customPath,
           FileManager.default.isExecutableFile(atPath: custom) {
            return custom
        }
        let candidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0)
        } ?? "claude"
    }

    private static func launchInTerminal(
        command: String,
        cwd: String?,
        terminalApp: String?
    ) {
        let terminal = terminalApp ?? detectTerminal()
        let escapedCmd = command.escapedForAppleScript
        let script = buildTerminalScript(
            terminal: terminal,
            command: escapedCmd,
            cwd: cwd
        )
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(
                fileURLWithPath: "/usr/bin/osascript"
            )
            let pipe = Pipe()
            process.standardInput = pipe
            try? process.run()
            pipe.fileHandleForWriting.write(
                script.data(using: .utf8) ?? Data()
            )
            pipe.fileHandleForWriting.closeFile()
        }
    }

    private static func buildTerminalScript(
        terminal: String,
        command: String,
        cwd: String?
    ) -> String {
        if terminal == "iterm" {
            return buildITermScript(command: command, cwd: cwd)
        }
        return buildTerminalAppScript(command: command, cwd: cwd)
    }

    private static func buildITermScript(
        command: String,
        cwd: String?
    ) -> String {
        let cdPart: String
        if let cwd {
            let escaped = cwd.escapedForAppleScript
            cdPart = """
                        tell current session of current window
                            write text "cd \(escaped)"
                        end tell

            """
        } else {
            cdPart = ""
        }
        return """
            tell application "iTerm2"
                if (count of windows) is 0 then
                    create window with default profile
                else
                    tell current window
                        create tab with default profile
                    end tell
                end if
            \(cdPart)    tell current session of current window
                    write text "\(command)"
                end tell
                activate
            end tell
            """
    }

    private static func buildTerminalAppScript(
        command: String,
        cwd: String?
    ) -> String {
        let cdClause: String
        if let cwd {
            let escaped = cwd.escapedForAppleScript
            cdClause = "cd \(escaped) && "
        } else {
            cdClause = ""
        }
        return """
            tell application "Terminal"
                do script "\(cdClause)\(command)"
                activate
            end tell
            """
    }

    private static func detectTerminal() -> String {
        let iterm = "/Applications/iTerm.app"
        if FileManager.default.fileExists(atPath: iterm) {
            return "iterm"
        }
        return "terminal"
    }

    // MARK: - Helpers

    @Sendable
    private static func openApp(bundleID: String) {
        DispatchQueue.main.async {
            if let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleID
            ) {
                NSWorkspace.shared.openApplication(
                    at: url,
                    configuration: .init()
                )
            }
        }
    }

    @Sendable
    private static func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        DispatchQueue.main.async {
            NSWorkspace.shared.open(url)
        }
    }

private static func stableID(_ input: String) -> String {
        let data = Data(input.utf8)
        var hash: UInt64 = 5381
        for byte in data {
            hash = ((hash &<< 5) &+ hash) &+ UInt64(byte)
        }
        return String(hash, radix: 36)
    }

    private static func iconForProvider(
        _ provider: AIProvider
    ) -> String {
        switch provider {
        case .claudeCode: "terminal"
        case .claudeDesktop: "brain"
        case .codex: "terminal.fill"
        }
    }

    private static func sessionSubtitle(
        _ session: AISession
    ) -> String {
        var parts: [String] = []
        parts.append(providerLabel(session.provider))
        if let project = session.project {
            parts.append(abbreviatePath(project))
        }
        if let model = session.model {
            parts.append(model)
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        parts.append(
            formatter.localizedString(
                for: session.timestamp, relativeTo: Date()
            )
        )
        return parts.joined(separator: " · ")
    }

    private static func providerLabel(
        _ provider: AIProvider
    ) -> String {
        switch provider {
        case .claudeCode: "Claude Code"
        case .claudeDesktop: "Claude Desktop"
        case .codex: "Codex"
        }
    }

    private static func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default
            .homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
