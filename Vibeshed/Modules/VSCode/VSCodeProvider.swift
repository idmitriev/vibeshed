import Foundation

struct VSCodeProvider: RecentProjectsProvider {
    typealias Config = VSCodeConfig

    static let moduleID = "vscode"
    static let displayName = "VS Code"
    static let iconName = "chevron.left.forwardslash.chevron.right"
    static var defaultConfig: VSCodeConfig { .init() }

    static func validate(_ config: VSCodeConfig) -> ConfigValidationResult {
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

    func enabledActions(_ config: VSCodeConfig) -> Set<String>? {
        config.enabledActions
    }

    func makeItems(config: VSCodeConfig) -> [RecentProjectItem] {
        let codePath = config.codePath
        let projects = VSCodeManager.discoverProjects(
            maxResults: config.maxResults,
            showFiles: config.showFiles,
            showRemote: config.showRemote,
            extraVariants: config.variants
        )
        return projects.map { project in
            let isRemote = project.isRemote
            let icon = isRemote ? "network" : "folder.badge.gearshape"
            let accent: ProjectAccent = isRemote ? .orange : .blue
            let subtitle = project.remoteLabel ?? abbreviatePath(project.path)
            let pathKeyword = project.path.lowercased()
                .replacingOccurrences(of: "/", with: " ")
            let path = project.path
            return RecentProjectItem(
                stableInput: project.path,
                title: project.name,
                subtitle: subtitle,
                isOpen: project.isOpen,
                listIcon: icon,
                accent: accent,
                trailingIcon: isRemote ? "network" : nil,
                trailingIconAccent: .orange,
                trailingLabel: project.variant,
                keywords: [
                    "vscode", "code", "project", "editor",
                    project.name.lowercased(), pathKeyword,
                ],
                previewRows: [
                    ProjectMetaRow(
                        icon: "folder", label: "Path",
                        value: abbreviatePath(project.path), selectable: true
                    ),
                ],
                previewPills: [
                    ProjectPill(
                        text: isRemote ? "Remote" : "Project",
                        icon: icon, accent: accent
                    ),
                    ProjectPill(text: project.variant, accent: .secondary),
                ],
                open: { VSCodeManager.openProject(path: path, codePath: codePath) }
            )
        }
    }
}
