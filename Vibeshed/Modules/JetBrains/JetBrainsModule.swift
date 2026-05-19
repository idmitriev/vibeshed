import Foundation
import OSLog
import SwiftUI

actor JetBrainsModule: ModuleConfigurable {
    let id = "jetbrains"
    let displayName = "JetBrains"
    let iconName = "hammer"
    var isEnabled = true

    typealias Config = JetBrainsConfig
    static var defaultConfig: Config? { .init() }

    private var config: JetBrainsConfig = .init()
    private var context: ModuleContext?
    private var cachedProjects: [JetBrainsProject] = []
    private var lastCacheTime: Date = .distantPast
    private let cacheTTL: TimeInterval = 5
    private let log = Log.module("jetbrains")

    func initialize(context: ModuleContext) async throws {
        self.context = context
        refreshCache()
        if config.openInNewWindow {
            JetBrainsManager.applyOpenInNewWindow(
                enabledIDEs: config.enabledIDEs
            )
        }
        log.info(
            "JetBrains module initialized (\(self.cachedProjects.count, privacy: .public) projects found)"
        )
    }

    func teardown() async {
        cachedProjects = []
    }

    func configDidUpdate(_ config: JetBrainsConfig) async {
        self.config = config
        refreshCache()
        if config.openInNewWindow {
            JetBrainsManager.applyOpenInNewWindow(
                enabledIDEs: config.enabledIDEs
            )
        }
        log.debug(
            "Config updated, cache refreshed (\(self.cachedProjects.count, privacy: .public) projects)"
        )
    }

    static func validate(
        _ config: JetBrainsConfig
    ) -> ConfigValidationResult {
        var errors: [String] = []
        if config.maxResults < 1 || config.maxResults > 100 {
            errors.append("maxResults must be between 1 and 100")
        }
        if let enabled = config.enabledIDEs {
            let validTags = Set(
                JetBrainsIDEInfo.known.map(\.tag)
            )
            let invalid = enabled.subtracting(validTags)
            if !invalid.isEmpty {
                errors.append(
                    "Unknown IDE tags: \(invalid.sorted().joined(separator: ", "))"
                )
            }
        }
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    func provideActions(
        query _: String,
        scoring _: ScoringContext
    ) async -> [any Action] {
        refreshCacheIfNeeded()
        return buildActions()
    }

    // MARK: - Private

    private func refreshCacheIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastCacheTime) > cacheTTL else {
            return
        }
        refreshCache()
    }

    private func refreshCache() {
        cachedProjects = JetBrainsManager.discoverProjects(
            maxResults: config.maxResults,
            enabledIDEs: config.enabledIDEs
        )
        lastCacheTime = Date()
    }

    private func actionName(_ id: ActionID) -> String {
        id.actionName
    }

    private func buildActions() -> [JetBrainsAction] {
        let enabled = config.enabledActions
        var actions = buildProjectActions()

        if let enabled {
            actions = actions.filter {
                enabled.contains(actionName($0.id))
            }
        }
        return actions
    }

    private func buildProjectActions() -> [JetBrainsAction] {
        cachedProjects.enumerated().map { index, project in
            let subtitle = abbreviatePath(project.path)
            let score = max(0.3, 0.95 - Double(index) * 0.02)
            let pathKeyword = project.path.lowercased()
                .replacingOccurrences(of: "/", with: " ")

            return JetBrainsAction(
                id: ActionID(
                    module: "jetbrains",
                    name: "project.\(stableID(project))"
                ),
                title: project.name,
                subtitle: subtitle,
                iconName: iconForIDE(project.ideTag),
                relevanceScore: score,
                keywords: [
                    "jetbrains", project.ideTag,
                    project.ideName.lowercased(),
                    "project", "ide",
                    project.name.lowercased(), pathKeyword,
                ],
                projectPath: project.path,
                ideName: project.ideName,
                ideTag: project.ideTag,
                isOpen: project.isOpen,
                frameContext: project.frameTitle
            ) { _ in
                JetBrainsManager.openProject(project)
                return .dismiss
            }
        }
    }

    private func stableID(_ project: JetBrainsProject) -> String {
        let data = Data(project.path.utf8)
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

private func iconForIDE(_ tag: String) -> String {
    switch tag {
    case "idea": "lightbulb"
    case "pycharm": "atom"
    case "webstorm": "globe"
    case "datagrip": "cylinder.split.1x2"
    case "goland": "g.circle"
    case "rustrover": "gearshape.2"
    case "clion": "memorychip"
    case "rider": "bolt"
    case "phpstorm": "server.rack"
    case "rubymine": "diamond"
    case "studio": "iphone"
    default: "hammer"
    }
}
