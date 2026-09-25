import Foundation

struct JetBrainsProvider: RecentProjectsProvider {
    typealias Config = JetBrainsConfig

    static let moduleID = "jetbrains"
    static let displayName = "JetBrains"
    static let iconName = "hammer"
    static var defaultConfig: JetBrainsConfig {
        .init()
    }

    static func validate(_ config: JetBrainsConfig) -> ConfigValidationResult {
        var errors: [String] = []
        if config.maxResults < 1 || config.maxResults > 100 {
            errors.append("maxResults must be between 1 and 100")
        }
        if let enabled = config.enabledIDEs {
            let validTags = Set(JetBrainsIDEInfo.known.map(\.tag))
            let invalid = enabled.subtracting(validTags)
            if !invalid.isEmpty {
                errors.append(
                    "Unknown IDE tags: \(invalid.sorted().joined(separator: ", "))"
                )
            }
        }
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    func enabledActions(_ config: JetBrainsConfig) -> Set<String>? {
        config.enabledActions
    }

    func applySideEffects(config: JetBrainsConfig) {
        if config.openInNewWindow {
            JetBrainsManager.applyOpenInNewWindow(enabledIDEs: config.enabledIDEs)
        }
    }

    func makeItems(config: JetBrainsConfig) -> [RecentProjectItem] {
        let projects = JetBrainsManager.discoverProjects(
            maxResults: config.maxResults,
            enabledIDEs: config.enabledIDEs
        )
        return projects.map { project in
            let icon = iconForIDE(project.ideTag)
            let accent = accentForIDE(project.ideTag)
            let pathKeyword = project.path.lowercased()
                .replacingOccurrences(of: "/", with: " ")
            var previewRows = [
                ProjectMetaRow(
                    icon: "folder", label: "Path",
                    value: project.path, selectable: true
                ),
            ]
            if let context = project.frameTitle {
                previewRows.append(
                    ProjectMetaRow(
                        icon: "doc.text", label: "Last opened",
                        value: context, selectable: false
                    )
                )
            }
            return RecentProjectItem(
                stableInput: project.path,
                title: project.name,
                subtitle: abbreviatePath(project.path),
                isOpen: project.isOpen,
                listIcon: icon,
                accent: accent,
                trailingLabel: project.ideName,
                keywords: [
                    "jetbrains", project.ideTag,
                    project.ideName.lowercased(),
                    "project", "ide",
                    project.name.lowercased(), pathKeyword,
                ],
                previewRows: previewRows,
                previewPills: [
                    ProjectPill(text: project.ideName, icon: icon, accent: accent),
                ],
                open: { JetBrainsManager.openProject(project) }
            )
        }
    }
}

/// SF Symbol and accent per IDE tag.
private let ideStyles: [String: (icon: String, accent: ProjectAccent)] = [
    "idea": ("lightbulb", .purple),
    "pycharm": ("atom", .green),
    "webstorm": ("globe", .cyan),
    "datagrip": ("cylinder.split.1x2", .purple),
    "goland": ("g.circle", .blue),
    "rustrover": ("gearshape.2", .orange),
    "clion": ("memorychip", .green),
    "rider": ("bolt", .blue),
    "phpstorm": ("server.rack", .purple),
    "rubymine": ("diamond", .red),
    "studio": ("iphone", .green),
]

private func iconForIDE(_ tag: String) -> String {
    ideStyles[tag]?.icon ?? "hammer"
}

private func accentForIDE(_ tag: String) -> ProjectAccent {
    ideStyles[tag]?.accent ?? .secondary
}
