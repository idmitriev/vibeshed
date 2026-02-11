import AppKit
import Foundation

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

    func initialize(context: ModuleContext) async throws {
        self.context = context
    }

    func configDidUpdate(_ config: ApplicationConfig) async {
        self.config = config
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

        guard !query.isEmpty else { return actions }
        let lowered = query.lowercased()
        return actions.filter { action in
            action.title.lowercased().contains(lowered)
                || action.subtitle.lowercased().contains(lowered)
                || action.keywords.contains { $0.contains(lowered) }
        }
    }

    func provideParameterOptions(
        for parameterID: String,
        in actionID: ActionID,
        query: String
    ) async -> [ParameterOption] {
        guard parameterID == "app" else { return [] }

        let cfg = config
        let actionName = actionID.rawValue

        // launch shows all apps; focus/quit show only running
        let showAll = actionName.hasSuffix(".launch") && !cfg.showRunningOnly

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
                iconName: "app"
            )
        }

        guard !query.isEmpty else { return options }
        let lowered = query.lowercased()
        return options.filter { $0.label.lowercased().contains(lowered) }
    }

    // MARK: - Build Actions

    private func buildActions() -> [ApplicationAction] {
        let mgr = appManager

        var actions: [ApplicationAction] = []

        // MARK: Launch Application
        actions.append(ApplicationAction(
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
        })

        // MARK: Focus Application
        actions.append(ApplicationAction(
            id: ActionID(module: "application", name: "focus"),
            title: "Focus Application",
            subtitle: "Activate a running application or cycle its windows",
            iconName: "app.badge.checkmark",
            relevanceScore: 0.85,
            keywords: ["focus", "switch", "activate", "application", "app", "cycle"],
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
            let focused = await MainActor.run { mgr.focusApplication(app) }
            if !focused {
                return .showResult(title: "Error", body: "Failed to focus application")
            }
            return .dismiss
        })

        // MARK: Quit Application
        actions.append(ApplicationAction(
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
        })

        return actions
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
                appBundleURL: bundleURL
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
