import AppKit
import Foundation
import OSLog

actor ApplicationModule: ModuleConfigurable {
    let id = "application"
    let displayName = "Applications"
    let iconName = "app.badge"
    var isEnabled = true

    typealias Config = ApplicationConfig
    static var defaultConfig: Config? { .init() }

    private var config: ApplicationConfig = .init()
    private let appManager = ApplicationManager()
    private var context: ModuleContext?
    private let log = Log.module("application")

    func initialize(context: ModuleContext) async throws {
        self.context = context
        log.info("Application module initialized")
    }

    func configDidUpdate(_ config: ApplicationConfig) async {
        self.config = config
        log.debug("Config updated")
    }

    static func validate(_ config: ApplicationConfig) -> ConfigValidationResult {
        .valid
    }

    func provideActions(query: String, scoring: ScoringContext) async -> [any Action] {
        let cfg = config
        let excluded = Set(cfg.excludedBundleIDs)

        var actions: [any Action] = buildActions()

        // Add per-app top-level actions
        let apps: [AppInfo]
        if cfg.showRunningOnly {
            apps = await MainActor.run { appManager.listRunningApplications() }
        } else {
            apps = await MainActor.run { appManager.listInstalledApplications() }
        }

        let mgr = appManager
        for app in apps where !excluded.contains(app.id) {
            actions.append(buildAppAction(for: app, manager: mgr))
        }

        return actions
    }

    func provideParameterOptions(
        for parameterID: String,
        in actionID: ActionID,
        query: String
    ) async -> [ParameterOption] {
        guard parameterID == "app" else { return [] }

        let cfg = config
        let actionName = actionID.rawValue

        // launch/launchOrFocus show all apps; focus/quit show only running
        let showAll = (actionName.hasSuffix(".launch") || actionName.hasSuffix(".launchOrFocus"))
            && !cfg.showRunningOnly

        let apps: [AppInfo]
        if showAll {
            apps = await MainActor.run { appManager.listInstalledApplications() }
        } else {
            apps = await MainActor.run { appManager.listRunningApplications() }
        }

        let excluded = Set(cfg.excludedBundleIDs)
        let filtered = apps.filter { !excluded.contains($0.id) }

        let options = filtered.map { app in
            ParameterOption(
                id: app.id,
                label: app.isRunning ? app.displayLabel : app.name,
                iconName: "app",
                iconURL: app.bundleURL
            )
        }

        return options
    }

    // MARK: - Build Actions

    private func buildActions() -> [ApplicationAction] {
        [buildLaunchAction(), buildLaunchOrFocusAction(), buildQuitAction()]
    }

    private func buildLaunchAction() -> ApplicationAction {
        let mgr = appManager
        return ApplicationAction(
            id: ActionID(module: "application", name: "launch"),
            title: "Launch Application",
            subtitle: "Launch or activate an application",
            iconName: "arrow.up.forward.app",
            relevanceScore: 0.85,
            keywords: ["launch", "open", "start", "run", "application", "app"],
            parameters: [
                ActionParameter(
                    id: "app",
                    label: "Application",
                    type: .dynamicSelection(hint: "app"),
                    isRequired: true
                ),
            ]
        ) { values in
            guard let bundleID = values["app"] as? String else {
                return .showResult(title: "Error", body: "No application selected")
            }
            let apps = await MainActor.run { mgr.listInstalledApplications() }
            guard let app = apps.first(where: { $0.id == bundleID }) else {
                return .showResult(title: "Error", body: "Application not found")
            }
            try await mgr.launchApplication(app)
            return .dismiss
        }
    }

    private func buildLaunchOrFocusAction() -> ApplicationAction {
        let mgr = appManager
        return ApplicationAction(
            id: ActionID(module: "application", name: "launchOrFocus"),
            title: "Launch or Focus Application",
            subtitle: "Launch if not running, focus or cycle windows if running",
            iconName: "arrow.up.forward.app.fill",
            relevanceScore: 0.9,
            keywords: ["launch", "focus", "open", "switch", "activate", "cycle", "app"],
            parameters: [
                ActionParameter(
                    id: "app",
                    label: "Application",
                    type: .dynamicSelection(hint: "app"),
                    isRequired: true
                ),
            ]
        ) { values in
            guard let bundleID = values["app"] as? String else {
                return .showResult(title: "Error", body: "No application selected")
            }
            let apps = await MainActor.run { mgr.listInstalledApplications() }
            guard let app = apps.first(where: { $0.id == bundleID }) else {
                return .showResult(title: "Error", body: "Application not found")
            }
            if app.isRunning {
                let focused = await MainActor.run { mgr.focusApplication(app) }
                if !focused {
                    return .showResult(title: "Error", body: "Failed to focus \(app.name)")
                }
            } else {
                try await mgr.launchApplication(app)
            }
            return .dismiss
        }
    }

    private func buildQuitAction() -> ApplicationAction {
        let mgr = appManager
        return ApplicationAction(
            id: ActionID(module: "application", name: "quit"),
            title: "Quit Application",
            subtitle: "Quit a running application",
            iconName: "xmark.app",
            relevanceScore: 0.7,
            keywords: ["quit", "close", "terminate", "kill", "application", "app", "exit"],
            parameters: [
                ActionParameter(
                    id: "app",
                    label: "Application",
                    type: .dynamicSelection(hint: "app"),
                    isRequired: true
                ),
            ]
        ) { values in
            guard let bundleID = values["app"] as? String else {
                return .showResult(title: "Error", body: "No application selected")
            }
            let apps = await MainActor.run { mgr.listRunningApplications() }
            guard let app = apps.first(where: { $0.id == bundleID }) else {
                return .showResult(title: "Error", body: "Application is not running")
            }
            let terminated = await MainActor.run { mgr.quitApplication(app) }
            if !terminated {
                return .showResult(title: "Error", body: "Failed to quit application")
            }
            return .dismiss
        }
    }

    // MARK: - Per-App Top-Level Action

    private func buildAppAction(for app: AppInfo, manager mgr: ApplicationManager) -> ApplicationAction {
        let bundleURL = app.bundleURL

        if app.isRunning {
            let subtitle = app.windowCount > 0
                ? "Running · \(app.windowCount) window\(app.windowCount == 1 ? "" : "s")"
                : "Running"
            return ApplicationAction(
                id: ActionID(module: "application", name: "app.\(app.id)"),
                title: app.name,
                subtitle: subtitle,
                relevanceScore: 0.75,
                keywords: ["app", "application", app.name.lowercased()],
                appBundleURL: bundleURL,
                isRunning: true
            ) { _ in
                let apps = await MainActor.run { mgr.listRunningApplications() }
                guard let current = apps.first(where: { $0.id == app.id }) else {
                    // No longer running — launch instead
                    try await mgr.launchApplication(app)
                    return .dismiss
                }
                let focused = await MainActor.run { mgr.focusApplication(current) }
                if !focused {
                    return .showResult(title: "Error", body: "Failed to focus \(app.name)")
                }
                return .dismiss
            }
        } else {
            return ApplicationAction(
                id: ActionID(module: "application", name: "app.\(app.id)"),
                title: app.name,
                subtitle: "Launch",
                relevanceScore: 0.6,
                keywords: ["app", "application", "launch", app.name.lowercased()],
                appBundleURL: bundleURL
            ) { _ in
                try await mgr.launchApplication(app)
                return .dismiss
            }
        }
    }
}
