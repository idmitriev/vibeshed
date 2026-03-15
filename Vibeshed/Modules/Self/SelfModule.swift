import AppKit
import Foundation
import OSLog

struct ModuleStatusInfo: Sendable {
    struct Entry: Sendable {
        let id: String
        let status: Status
        let message: String?

        enum Status: Sendable {
            case loaded
            case configError
            case permissionError
        }
    }

    let entries: [Entry]
}

actor SelfModule: ModuleConfigurable {
    let id = "self"
    let displayName = "Vibeshed"
    let iconName = "sparkle"
    var isEnabled = true

    typealias Config = SelfConfig
    static var defaultConfig: Config? { .init() }

    private var config = SelfConfig()
    private var context: ModuleContext?
    private let log = Log.module("self")
    private let configFileURL: URL
    private let configDirURL: URL
    private let reloadConfig: @Sendable () async -> Void
    private let getModuleStatus: @Sendable () async -> ModuleStatusInfo

    init(
        configFileURL: URL,
        configDirURL: URL,
        reloadConfig: @escaping @Sendable () async -> Void,
        getModuleStatus: @escaping @Sendable () async -> ModuleStatusInfo
    ) {
        self.configFileURL = configFileURL
        self.configDirURL = configDirURL
        self.reloadConfig = reloadConfig
        self.getModuleStatus = getModuleStatus
    }

    func initialize(context: ModuleContext) async throws {
        self.context = context
        log.info("Self module initialized")
    }

    func configDidUpdate(_ config: SelfConfig) async {
        self.config = config
        log.debug("Config updated")
    }

    static func validate(_ config: SelfConfig) -> ConfigValidationResult {
        .valid
    }

    func provideActions(
        query: String,
        scoring: ScoringContext
    ) async -> [any Action] {
        let actions = buildActions()

        return actions
    }

    // MARK: - Build Actions

    private func buildActions() -> [SelfAction] {
        let enabled = config.enabledActions
        var actions: [SelfAction] = []

        actions.append(contentsOf: buildConfigActions())
        actions.append(contentsOf: buildStatusActions())
        actions.append(contentsOf: buildUtilityActions())

        if let enabled {
            return actions.filter { enabled.contains(actionName($0.id)) }
        }
        return actions
    }

    private func actionName(_ id: ActionID) -> String {
        id.actionName
    }

    private func buildConfigActions() -> [SelfAction] {
        let fileURL = configFileURL
        let dirURL = configDirURL
        let reload = reloadConfig

        return [
            SelfAction(
                id: ActionID(module: "self", name: "openConfig"),
                title: "Open Config File",
                subtitle: fileURL.path,
                iconName: "doc.text",
                relevanceScore: 0.85,
                keywords: [
                    "config", "configuration", "settings",
                    "preferences", "yaml", "edit", "vibeshed",
                ]
            ) { _ in
                await MainActor.run { _ = NSWorkspace.shared.open(fileURL) }
                return .dismiss
            },
            SelfAction(
                id: ActionID(module: "self", name: "openConfigDir"),
                title: "Open Config Directory",
                subtitle: dirURL.path,
                iconName: "folder",
                relevanceScore: 0.7,
                keywords: [
                    "config", "directory", "folder",
                    "vibeshed", "open",
                ]
            ) { _ in
                await MainActor.run { _ = NSWorkspace.shared.open(dirURL) }
                return .dismiss
            },
            SelfAction(
                id: ActionID(module: "self", name: "reloadConfig"),
                title: "Reload Config",
                subtitle: "Re-read config file from disk",
                iconName: "arrow.clockwise",
                relevanceScore: 0.8,
                keywords: [
                    "reload", "refresh", "config",
                    "configuration", "vibeshed",
                ]
            ) { _ in
                await reload()
                return .showResult(
                    title: "Config Reloaded",
                    body: "Configuration has been re-read from disk"
                )
            },
        ]
    }

    private func buildStatusActions() -> [SelfAction] {
        let statusProvider = getModuleStatus

        return [
            SelfAction(
                id: ActionID(module: "self", name: "moduleStatus"),
                title: "Module Status",
                subtitle: "View loaded and pending modules",
                iconName: "list.bullet.rectangle",
                relevanceScore: 0.75,
                keywords: [
                    "module", "status", "loaded", "error",
                    "permission", "vibeshed", "debug",
                ]
            ) { _ in
                let status = await statusProvider()
                let subActions: [SelfAction] = status.entries.map { entry in
                    let (icon, detail) = Self.statusDisplay(entry)
                    return SelfAction(
                        id: ActionID(
                            module: "self",
                            name: "module.\(entry.id)"
                        ),
                        title: entry.id,
                        subtitle: detail,
                        iconName: icon,
                        relevanceScore: 0.5
                    ) { _ in
                        .dismiss
                    }
                }
                return .pushActions(subActions)
            }
        ]
    }

    private static func statusDisplay(
        _ entry: ModuleStatusInfo.Entry
    ) -> (icon: String, detail: String) {
        switch entry.status {
        case .loaded:
            return ("checkmark.circle.fill", "Loaded")
        case .configError:
            let msg = entry.message ?? "Unknown config error"
            return ("xmark.circle.fill", "Config error: \(msg)")
        case .permissionError:
            let msg = entry.message ?? "Missing permissions"
            return ("exclamationmark.triangle.fill", msg)
        }
    }

    private func buildUtilityActions() -> [SelfAction] {
        [
            SelfAction(
                id: ActionID(module: "self", name: "openLogs"),
                title: "Open Logs",
                subtitle: "Open Console.app for Vibeshed logs",
                iconName: "text.alignleft",
                relevanceScore: 0.7,
                keywords: [
                    "log", "logs", "console", "debug",
                    "vibeshed", "diagnose",
                ]
            ) { _ in
                await MainActor.run {
                    let bundleID = Bundle.main.bundleIdentifier ?? "com.ivandmitriev.Vibeshed"
                    let url = URL(
                        string: "x-apple.systempreferences:com.apple.Console"
                    )
                    if let consoleURL = NSWorkspace.shared.urlForApplication(
                        withBundleIdentifier: "com.apple.Console"
                    ) {
                        let config = NSWorkspace.OpenConfiguration()
                        config.arguments = ["--process", bundleID]
                        NSWorkspace.shared.openApplication(
                            at: consoleURL,
                            configuration: config
                        )
                    } else if let url {
                        NSWorkspace.shared.open(url)
                    }
                }
                return .dismiss
            },
            SelfAction(
                id: ActionID(module: "self", name: "quit"),
                title: "Quit Vibeshed",
                subtitle: "Exit the application",
                iconName: "xmark.square",
                relevanceScore: 0.6,
                keywords: [
                    "quit", "exit", "close", "terminate",
                    "vibeshed", "stop",
                ]
            ) { _ in
                await MainActor.run {
                    NSApplication.shared.terminate(nil)
                }
                return .dismiss
            },
        ]
    }
}
