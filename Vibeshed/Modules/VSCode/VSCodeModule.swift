import AppKit
import Foundation
import OSLog
import SwiftUI

actor VSCodeModule: ModuleConfigurable {
    let id = "vscode"
    let displayName = "VS Code"
    let iconName = "chevron.left.forwardslash.chevron.right"
    var isEnabled = true

    typealias Config = VSCodeConfig
    static var defaultConfig: Config? { .init() }

    private var config: VSCodeConfig = .init()
    private var context: ModuleContext?
    private var cachedProjects: [VSCodeProject] = []
    private var lastCacheTime: Date = .distantPast
    private let cacheTTL: TimeInterval = 5
    private let log = Log.module("vscode")

    func initialize(context: ModuleContext) async throws {
        self.context = context
        refreshCache()
        log.info("VSCode module initialized (\(self.cachedProjects.count, privacy: .public) projects found)")
    }

    func teardown() async {
        cachedProjects = []
    }

    func configDidUpdate(_ config: VSCodeConfig) async {
        self.config = config
        refreshCache()
        log.debug("Config updated, cache refreshed (\(self.cachedProjects.count, privacy: .public) projects)")
    }

    static func validate(
        _ config: VSCodeConfig
    ) -> ConfigValidationResult {
        var errors: [String] = []
        if config.maxResults < 1 || config.maxResults > 100 {
            errors.append("maxResults must be between 1 and 100")
        }
        if let path = config.codePath,
           !path.isEmpty,
           !FileManager.default.fileExists(atPath: path) {
            errors.append("codePath does not exist: \(path)")
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

    // MARK: - Private

    private func refreshCacheIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastCacheTime) > cacheTTL else {
            return
        }
        refreshCache()
    }

    private func refreshCache() {
        cachedProjects = VSCodeManager.discoverProjects(
            maxResults: config.maxResults,
            showFiles: config.showFiles,
            showRemote: config.showRemote,
            extraVariants: config.variants
        )
        lastCacheTime = Date()
    }

    private func actionName(_ id: ActionID) -> String {
        let raw = id.rawValue
        guard let dotIndex = raw.firstIndex(of: ".") else { return raw }
        return String(raw[raw.index(after: dotIndex)...])
    }

    private func buildActions() -> [VSCodeAction] {
        let enabled = config.enabledActions
        var actions: [VSCodeAction] = []

        actions.append(contentsOf: buildProjectActions())

        if let enabled {
            return actions.filter { enabled.contains(actionName($0.id)) }
        }
        return actions
    }

    private func buildProjectActions() -> [VSCodeAction] {
        let codePath = config.codePath
        return cachedProjects.enumerated().map { index, project in
            let itemType: VSCodeItemType = project.isRemote
                ? .remote : .project
            let subtitle = projectSubtitle(project)
            let score = max(0.3, 0.95 - Double(index) * 0.02)
            let pathKeyword = project.path.lowercased()
                .replacingOccurrences(of: "/", with: " ")
            return VSCodeAction(
                id: ActionID(
                    module: "vscode",
                    name: "project.\(stableID(project))"
                ),
                title: project.name,
                subtitle: subtitle,
                iconName: iconForProject(project),
                relevanceScore: score,
                keywords: [
                    "vscode", "code", "project", "editor",
                    project.name.lowercased(), pathKeyword,
                ],
                projectPath: project.path,
                vscodeItemType: itemType,
                variant: project.variant,
                isOpen: project.isOpen
            ) { [codePath] _ in
                VSCodeManager.openProject(
                    path: project.path, codePath: codePath
                )
                return .dismiss
            }
        }
    }

    private func projectSubtitle(_ project: VSCodeProject) -> String {
        if let label = project.remoteLabel {
            return label
        }
        return abbreviatePath(project.path)
    }

    private func iconForProject(_ project: VSCodeProject) -> String {
        if project.isRemote {
            return "network"
        }
        return "folder.badge.gearshape"
    }

    private func stableID(_ project: VSCodeProject) -> String {
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
