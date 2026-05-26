import Foundation
import OSLog
import SwiftUI

actor ZedModule: ModuleConfigurable {
    let id = "zed"
    let displayName = "Zed"
    let iconName = "pencil.and.outline"
    var isEnabled = true

    typealias Config = ZedConfig
    static var defaultConfig: Config? { .init() }

    private var config: ZedConfig = .init()
    private var context: ModuleContext?
    private var cachedWorkspaces: [ZedWorkspace] = []
    private var lastCacheTime: Date = .distantPast
    private let cacheTTL: TimeInterval = 5
    private let log = Log.module("zed")

    func initialize(context: ModuleContext) async throws {
        self.context = context
        refreshCache()
        log.info("Zed module initialized (\(self.cachedWorkspaces.count, privacy: .public) workspaces found)")
    }

    func teardown() async {
        cachedWorkspaces = []
    }

    func configDidUpdate(_ config: ZedConfig) async {
        self.config = config
        refreshCache()
        log.debug("Config updated, cache refreshed (\(self.cachedWorkspaces.count, privacy: .public) workspaces)")
    }

    static func validate(_ config: ZedConfig) -> ConfigValidationResult {
        var errors: [String] = []
        if config.maxResults < 1 || config.maxResults > 100 {
            errors.append("maxResults must be between 1 and 100")
        }
        if let path = config.zedPath,
           !path.isEmpty,
           !FileManager.default.fileExists(atPath: path) {
            errors.append("zedPath does not exist: \(path)")
        }
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    func provideActions(
        query: String,
        scoring: ScoringContext
    ) async -> [any Action] {
        refreshCacheIfNeeded()
        return buildActions()
    }

    // MARK: - Private

    private func refreshCacheIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastCacheTime) > cacheTTL else { return }
        refreshCache()
    }

    private func refreshCache() {
        cachedWorkspaces = ZedManager.discoverWorkspaces(
            maxResults: config.maxResults,
            showRemote: config.showRemote
        )
        lastCacheTime = Date()
    }

    private func buildActions() -> [ZedAction] {
        let enabled = config.enabledActions
        let zedPath = config.zedPath
        var actions: [ZedAction] = []

        actions.append(contentsOf: cachedWorkspaces.enumerated().map { index, ws in
            let score = max(0.3, 0.95 - Double(index) * 0.02)
            let pathKeyword = ws.path.lowercased()
                .replacingOccurrences(of: "/", with: " ")
            return ZedAction(
                id: ActionID(module: "zed", name: "project.\(stableID(ws))"),
                title: ws.name,
                subtitle: ws.isRemote
                    ? "\(ws.remoteHost ?? "remote"):\(ws.path)"
                    : abbreviatePath(ws.path),
                iconName: ws.isRemote ? "network" : "folder",
                relevanceScore: score,
                keywords: [
                    "zed", "editor", "project",
                    ws.name.lowercased(), pathKeyword,
                ],
                projectPath: ws.path,
                isRemote: ws.isRemote,
                remoteHost: ws.remoteHost,
                isOpen: ws.isOpen
            ) { [zedPath] _ in
                ZedManager.openWorkspace(path: ws.path, zedPath: zedPath)
                return .dismiss
            }
        })

        if let enabled {
            return actions.filter { enabled.contains($0.id.actionName) }
        }
        return actions
    }

    private func stableID(_ workspace: ZedWorkspace) -> String {
        let data = Data(workspace.path.utf8)
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
