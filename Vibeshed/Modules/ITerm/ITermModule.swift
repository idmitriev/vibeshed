import Foundation
import OSLog

actor ITermModule: ModuleConfigurable {
    let id = "iterm"
    let displayName = "iTerm"
    let iconName = "terminal"
    var isEnabled = true

    typealias Config = ITermConfig
    static var defaultConfig: Config? { .init() }

    static var requiredPermissions: Set<Permission> { [.automation] }

    private var config: ITermConfig = .init()
    private var context: ModuleContext?
    private let log = Log.module("iterm")

    func initialize(context: ModuleContext) async throws {
        self.context = context
        log.info("iTerm module initialized")
    }

    func teardown() async {}

    func configDidUpdate(_ config: ITermConfig) async {
        self.config = config
        log.debug("Config updated")
    }

    static func validate(
        _ config: ITermConfig
    ) -> ConfigValidationResult {
        var errors: [String] = []
        if config.maxResults < 1 || config.maxResults > 50 {
            errors.append("maxResults must be between 1 and 50")
        }
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    func provideActions(
        query: String,
        scoring: ScoringContext
    ) async -> [any Action] {
        let actions = await buildActions()

        guard !query.isEmpty else { return actions }
        let lowered = query.lowercased()
        return actions.filter { action in
            action.title.lowercased().contains(lowered)
                || action.subtitle.lowercased().contains(lowered)
                || action.keywords.contains { $0.contains(lowered) }
        }
    }

    // MARK: - Private

    private func actionName(_ id: ActionID) -> String {
        let raw = id.rawValue
        guard let dotIndex = raw.firstIndex(of: ".") else {
            return raw
        }
        return String(raw[raw.index(after: dotIndex)...])
    }

    private func buildActions() async -> [ITermAction] {
        let enabled = config.enabledActions
        var actions: [ITermAction] = []

        actions.append(contentsOf: buildStaticActions())
        actions.append(contentsOf: buildCommandActions())

        if ITermManager.isRunning() {
            let sessions = await buildSessionActions()
            actions.append(contentsOf: sessions)
        }

        if let enabled {
            return actions.filter {
                enabled.contains(actionName($0.id))
            }
        }
        return actions
    }

    // MARK: - Static Actions

    private func buildStaticActions() -> [ITermAction] {
        let config = self.config
        var actions: [ITermAction] = []
        actions.append(buildNewTabAction(config: config))
        actions.append(buildNewWindowAction(config: config))
        actions.append(buildRunCommandAction(config: config))
        return actions
    }

    private func buildNewTabAction(
        config: ITermConfig
    ) -> ITermAction {
        ITermAction(
            id: ActionID(module: "iterm", name: "newTab"),
            title: "New Tab",
            subtitle: "Open a new iTerm tab",
            iconName: "plus.rectangle",
            relevanceScore: 0.85,
            keywords: [
                "iterm", "terminal", "tab", "new", "shell",
            ],
            itermItemType: .newTab
        ) { [config] _ in
            try await ITermManager.createTab(
                profile: config.defaultProfile,
                command: nil
            )
            return .dismiss
        }
    }

    private func buildNewWindowAction(
        config: ITermConfig
    ) -> ITermAction {
        ITermAction(
            id: ActionID(module: "iterm", name: "newWindow"),
            title: "New Window",
            subtitle: "Open a new iTerm window",
            iconName: "macwindow.badge.plus",
            relevanceScore: 0.83,
            keywords: [
                "iterm", "terminal", "window", "new", "shell",
            ],
            itermItemType: .newWindow
        ) { [config] _ in
            try await ITermManager.createWindow(
                profile: config.defaultProfile,
                command: nil
            )
            return .dismiss
        }
    }

    private func buildRunCommandAction(
        config: ITermConfig
    ) -> ITermAction {
        ITermAction(
            id: ActionID(module: "iterm", name: "runCommand"),
            title: "Run Command",
            subtitle: "Run a command in a new iTerm tab",
            iconName: "text.cursor",
            relevanceScore: 0.88,
            keywords: [
                "iterm", "terminal", "run", "command",
                "execute", "shell",
            ],
            parameters: [
                ActionParameter(
                    id: "command",
                    label: "Command",
                    type: .text(
                        placeholder: "Enter command to run..."
                    ),
                    isRequired: true
                ),
            ],
            itermItemType: .command
        ) { [config] values in
            guard let cmd = values["command"] as? String,
                  !cmd.isEmpty
            else {
                return .showResult(
                    title: "Run Command",
                    body: "Please enter a command to run"
                )
            }
            try await ITermManager.createTab(
                profile: config.defaultProfile,
                command: cmd
            )
            return .dismiss
        }
    }

    // MARK: - Command Actions

    private func buildCommandActions() -> [ITermAction] {
        guard let commands = config.commands else { return [] }
        let config = self.config
        return commands.enumerated().map { index, entry in
            let (name, command) = entry
            let score = max(0.3, 0.87 - Double(index) * 0.02)
            return ITermAction(
                id: ActionID(
                    module: "iterm",
                    name: "cmd.\(stableID(name))"
                ),
                title: name,
                subtitle: command,
                iconName: "text.cursor",
                relevanceScore: score,
                keywords: [
                    "iterm", "command",
                    name.lowercased(), command.lowercased(),
                ],
                itermItemType: .command
            ) { [config] _ in
                try await ITermManager.createTab(
                    profile: config.defaultProfile,
                    command: command
                )
                return .dismiss
            }
        }
    }

    // MARK: - Session Actions

    private func buildSessionActions() async -> [ITermAction] {
        let sessions: [ITermSession]
        do {
            sessions = try await ITermManager.listSessions()
        } catch {
            log.error("Failed to list iTerm sessions: \(error.localizedDescription, privacy: .public)")
            return []
        }

        let config = self.config
        let limit = config.maxResults
        return Array(
            sessions.prefix(limit).enumerated().map { idx, session in
                buildSessionAction(
                    session: session,
                    index: idx,
                    config: config
                )
            }
        )
    }

    private func buildSessionAction(
        session: ITermSession,
        index: Int,
        config: ITermConfig
    ) -> ITermAction {
        let subtitle = sessionSubtitle(
            session, config: config
        )
        let score = max(0.3, 0.92 - Double(index) * 0.02)
        let sid = session.sessionID
        var kw: [String] = [
            "iterm", "session", "terminal",
            session.name.lowercased(),
            session.profileName.lowercased(),
        ]
        if let cwd = session.cwd {
            kw.append(cwd.lowercased())
        }
        if let job = session.jobName {
            kw.append(job.lowercased())
        }

        return ITermAction(
            id: ActionID(
                module: "iterm",
                name: "session.\(stableID(sid))"
            ),
            title: session.name,
            subtitle: subtitle,
            iconName: "terminal",
            relevanceScore: score,
            keywords: kw,
            itermItemType: .session,
            sessionPath: session.cwd,
            jobName: session.jobName,
            profileName: session.profileName,
            isAtPrompt: session.isAtPrompt
        ) { _ in
            try await ITermManager.focusSession(id: sid)
            return .dismiss
        }
    }

    // MARK: - Helpers

    private func sessionSubtitle(
        _ session: ITermSession,
        config: ITermConfig
    ) -> String {
        var parts: [String] = []
        if config.showCWD, let cwd = session.cwd {
            parts.append(abbreviatePath(cwd))
        }
        if config.showJobName, let job = session.jobName {
            parts.append(job)
        }
        if parts.isEmpty {
            parts.append(session.profileName)
        }
        return parts.joined(separator: " · ")
    }

    private func stableID(_ input: String) -> String {
        let data = Data(input.utf8)
        var hash: UInt64 = 5381
        for byte in data {
            hash = ((hash &<< 5) &+ hash) &+ UInt64(byte)
        }
        return String(hash, radix: 36)
    }
}

private func abbreviatePath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if path.hasPrefix(home) {
        return "~" + path.dropFirst(home.count)
    }
    return path
}
