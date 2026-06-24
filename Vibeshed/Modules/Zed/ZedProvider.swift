import Foundation

struct ZedProvider: RecentProjectsProvider {
    typealias Config = ZedConfig

    static let moduleID = "zed"
    static let displayName = "Zed"
    static let iconName = "pencil.and.outline"
    static var defaultConfig: ZedConfig {
        .init()
    }

    static func validate(_ config: ZedConfig) -> ConfigValidationResult {
        var errors: [String] = []
        if config.maxResults < 1 || config.maxResults > 100 {
            errors.append("maxResults must be between 1 and 100")
        }
        if let path = config.zedPath,
           !path.isEmpty,
           !FileManager.default.fileExists(atPath: path)
        {
            errors.append("zedPath does not exist: \(path)")
        }
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    func enabledActions(_ config: ZedConfig) -> Set<String>? {
        config.enabledActions
    }

    func makeItems(config: ZedConfig) -> [RecentProjectItem] {
        let zedPath = config.zedPath
        let workspaces = ZedManager.discoverWorkspaces(
            maxResults: config.maxResults,
            showRemote: config.showRemote
        )
        return workspaces.map { ws in
            let isRemote = ws.isRemote
            let icon = isRemote ? "network" : "folder"
            let accent: ProjectAccent = isRemote ? .orange : .purple
            let subtitle = isRemote
                ? "\(ws.remoteHost ?? "remote"):\(ws.path)"
                : abbreviatePath(ws.path)
            let pathKeyword = ws.path.lowercased()
                .replacingOccurrences(of: "/", with: " ")
            let path = ws.path
            var previewPills = [
                ProjectPill(
                    text: isRemote ? "Remote" : "Project",
                    icon: icon, accent: accent
                ),
            ]
            if let host = ws.remoteHost {
                previewPills.append(ProjectPill(text: host, accent: .secondary))
            }
            return RecentProjectItem(
                stableInput: ws.path,
                title: ws.name,
                subtitle: subtitle,
                isOpen: ws.isOpen,
                listIcon: icon,
                accent: accent,
                trailingIcon: isRemote ? "network" : nil,
                trailingIconAccent: .orange,
                trailingLabel: "Zed",
                keywords: [
                    "zed", "editor", "project",
                    ws.name.lowercased(), pathKeyword,
                ],
                previewRows: [
                    ProjectMetaRow(
                        icon: "folder", label: "Path",
                        value: abbreviatePath(ws.path), selectable: true
                    ),
                ],
                previewPills: previewPills,
                open: { ZedManager.openWorkspace(path: path, zedPath: zedPath) }
            )
        }
    }
}
