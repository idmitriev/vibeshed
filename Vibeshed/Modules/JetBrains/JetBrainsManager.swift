import AppKit
import Foundation
import OSLog

private let log = Log.module("jetbrains")

// MARK: - Data Types

struct JetBrainsProject: Sendable {
    let name: String
    let path: String
    let ideName: String
    let ideTag: String
    let productCode: String
    let lastOpened: Date
    let frameTitle: String?
    let isOpen: Bool
    let appPath: String?
    let launchCommand: String?
}

struct ToolboxTool: Sendable {
    let productCode: String
    let displayName: String
    let tag: String
    let installLocation: String
    let launchCommand: String?
}

// MARK: - Known IDE types

struct JetBrainsIDEInfo {
    let dirPrefix: String
    let displayName: String
    let tag: String

    static let known: [JetBrainsIDEInfo] = [
        .init(dirPrefix: "IntelliJIdea", displayName: "IntelliJ IDEA", tag: "idea"),
        .init(dirPrefix: "PyCharm", displayName: "PyCharm", tag: "pycharm"),
        .init(dirPrefix: "WebStorm", displayName: "WebStorm", tag: "webstorm"),
        .init(dirPrefix: "DataGrip", displayName: "DataGrip", tag: "datagrip"),
        .init(dirPrefix: "GoLand", displayName: "GoLand", tag: "goland"),
        .init(dirPrefix: "RustRover", displayName: "RustRover", tag: "rustrover"),
        .init(dirPrefix: "CLion", displayName: "CLion", tag: "clion"),
        .init(dirPrefix: "Rider", displayName: "Rider", tag: "rider"),
        .init(dirPrefix: "PhpStorm", displayName: "PhpStorm", tag: "phpstorm"),
        .init(dirPrefix: "RubyMine", displayName: "RubyMine", tag: "rubymine"),
        .init(dirPrefix: "AndroidStudio", displayName: "Android Studio", tag: "studio"),
        .init(dirPrefix: "Idea", displayName: "IntelliJ IDEA CE", tag: "idea"),
    ]
}

// MARK: - Manager

enum JetBrainsManager {
    static func discoverProjects(
        maxResults: Int,
        enabledIDEs: Set<String>?
    ) -> [JetBrainsProject] {
        let toolboxTools = readToolboxState()
        let jbBase = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/JetBrains")

        guard let contents = try? FileManager.default
            .contentsOfDirectory(atPath: jbBase.path)
        else {
            log.debug("No JetBrains Application Support directory found")
            return []
        }

        var allProjects: [JetBrainsProject] = []

        for dir in contents {
            guard let ideInfo = matchIDE(dir) else { continue }
            if let enabled = enabledIDEs, !enabled.contains(ideInfo.tag) {
                continue
            }

            let xmlPath = jbBase
                .appendingPathComponent(dir)
                .appendingPathComponent("options/recentProjects.xml")
                .path

            guard FileManager.default.fileExists(atPath: xmlPath) else {
                continue
            }

            let tool = findToolboxTool(
                for: ideInfo, tools: toolboxTools
            )
            let projects = parseRecentProjects(
                at: xmlPath,
                ideInfo: ideInfo,
                tool: tool
            )
            allProjects.append(contentsOf: projects)
        }

        // Sort by last opened (most recent first)
        allProjects.sort { $0.lastOpened > $1.lastOpened }

        // Deduplicate by path, keeping most recent
        var seen = Set<String>()
        allProjects = allProjects.filter { seen.insert($0.path).inserted }

        return Array(allProjects.prefix(maxResults))
    }

    static func openProject(_ project: JetBrainsProject) {
        if let cmd = project.launchCommand,
           FileManager.default.isExecutableFile(atPath: cmd) {
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: cmd)
                process.arguments = [project.path]
                do {
                    try process.run()
                } catch {
                    log.warning(
                        "Launch command failed: \(error.localizedDescription, privacy: .public)"
                    )
                    fallbackOpen(project)
                }
            }
            return
        }
        fallbackOpen(project)
    }

    static func applyOpenInNewWindow(
        enabledIDEs: Set<String>?
    ) {
        let jbBase = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/JetBrains"
            )

        guard let contents = try? FileManager.default
            .contentsOfDirectory(atPath: jbBase.path)
        else {
            return
        }

        for dir in contents {
            guard let ideInfo = matchIDE(dir) else { continue }
            if let enabled = enabledIDEs,
               !enabled.contains(ideInfo.tag) {
                continue
            }

            let xmlPath = jbBase
                .appendingPathComponent(dir)
                .appendingPathComponent("options/ide.general.xml")
                .path

            patchOpenNewProject(at: xmlPath)
        }
    }

    // MARK: - Private

    private static func patchOpenNewProject(at path: String) {
        guard var content = try? String(
            contentsOfFile: path, encoding: .utf8
        ) else {
            return
        }

        let pattern =
            #"(<option\s+name="confirmOpenNewProject2"\s+value=")([^"]*)(")"#

        guard let regex = try? NSRegularExpression(
            pattern: pattern
        ) else {
            return
        }

        let nsRange = NSRange(
            content.startIndex..., in: content
        )

        if let match = regex.firstMatch(
            in: content, range: nsRange
        ) {
            guard let valueRange = Range(
                match.range(at: 2), in: content
            ) else { return }
            if content[valueRange] == "1" { return }
            content.replaceSubrange(valueRange, with: "1")
        } else if let range = content.range(
            of: #"<component name="GeneralSettings">"#
        ) {
            let line = "\n    <option name=" +
                "\"confirmOpenNewProject2\" value=\"1\" />"
            content.insert(
                contentsOf: line, at: range.upperBound
            )
        } else {
            return
        }

        try? content.write(
            toFile: path, atomically: true, encoding: .utf8
        )
        log.debug(
            "Set confirmOpenNewProject2=1 in \(path, privacy: .public)"
        )
    }

    private static func fallbackOpen(_ project: JetBrainsProject) {
        let url = URL(fileURLWithPath: project.path)
        if let appPath = project.appPath {
            let appURL = URL(fileURLWithPath: appPath)
            DispatchQueue.main.async {
                NSWorkspace.shared.open(
                    [url],
                    withApplicationAt: appURL,
                    configuration: .init()
                )
            }
        } else {
            DispatchQueue.main.async {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private static func matchIDE(
        _ dirName: String
    ) -> JetBrainsIDEInfo? {
        for info in JetBrainsIDEInfo.known {
            if dirName.hasPrefix(info.dirPrefix) {
                let suffix = String(dirName.dropFirst(info.dirPrefix.count))
                // Must be followed by version number or empty
                if suffix.isEmpty || suffix.first?.isNumber == true {
                    return info
                }
            }
        }
        return nil
    }

    private static func findToolboxTool(
        for ideInfo: JetBrainsIDEInfo,
        tools: [ToolboxTool]
    ) -> ToolboxTool? {
        tools.first { $0.tag == ideInfo.tag }
    }

    private static func readToolboxState() -> [ToolboxTool] {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/JetBrains/Toolbox/state.json"
            )
            .path

        guard let data = FileManager.default.contents(atPath: path) else {
            return []
        }

        guard let json = try? JSONSerialization.jsonObject(with: data)
            as? [String: Any],
            let tools = json["tools"] as? [[String: Any]]
        else {
            return []
        }

        return tools.compactMap { tool in
            guard let productCode = tool["productCode"] as? String,
                  let displayName = tool["displayName"] as? String,
                  let tag = tool["tag"] as? String,
                  let installLocation = tool["installLocation"] as? String
            else {
                return nil
            }
            return ToolboxTool(
                productCode: productCode,
                displayName: displayName,
                tag: tag,
                installLocation: installLocation,
                launchCommand: tool["launchCommand"] as? String
            )
        }
    }

    private static func parseRecentProjects(
        at xmlPath: String,
        ideInfo: JetBrainsIDEInfo,
        tool: ToolboxTool?
    ) -> [JetBrainsProject] {
        guard let data = FileManager.default.contents(atPath: xmlPath) else {
            log.debug("Cannot read \(xmlPath, privacy: .public)")
            return []
        }

        let parser = RecentProjectsXMLParser(
            ideInfo: ideInfo, tool: tool
        )
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.parse()
        return parser.projects
    }
}

// MARK: - XML Parser

private final class RecentProjectsXMLParser: NSObject,
    XMLParserDelegate {
    let ideInfo: JetBrainsIDEInfo
    let tool: ToolboxTool?
    var projects: [JetBrainsProject] = []

    private let homeDir = FileManager.default
        .homeDirectoryForCurrentUser.path

    // Parsing state
    private var currentEntryPath: String?
    private var currentFrameTitle: String?
    private var currentIsOpen = false
    private var currentActivationTimestamp: Int64?
    private var currentProductCode: String?
    private var inEntry = false

    init(ideInfo: JetBrainsIDEInfo, tool: ToolboxTool?) {
        self.ideInfo = ideInfo
        self.tool = tool
    }

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes: [String: String] = [:]
    ) {
        switch elementName {
        case "entry":
            if let key = attributes["key"] {
                inEntry = true
                currentEntryPath = expandUserHome(key)
                currentFrameTitle = nil
                currentIsOpen = false
                currentActivationTimestamp = nil
                currentProductCode = nil
            }

        case "RecentProjectMetaInfo" where inEntry:
            currentFrameTitle = attributes["frameTitle"]
            if attributes["opened"] == "true" {
                currentIsOpen = true
            }

        case "option" where inEntry:
            if let name = attributes["name"],
               let value = attributes["value"] {
                switch name {
                case "activationTimestamp":
                    currentActivationTimestamp = Int64(value)
                case "productionCode":
                    currentProductCode = value
                default:
                    break
                }
            }

        default:
            break
        }
    }

    func parser(
        _: XMLParser,
        didEndElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?
    ) {
        guard elementName == "entry", inEntry,
              let path = currentEntryPath
        else {
            return
        }
        inEntry = false

        let timestamp = currentActivationTimestamp ?? 0
        let date = Date(
            timeIntervalSince1970: Double(timestamp) / 1000.0
        )
        let name = URL(fileURLWithPath: path).lastPathComponent

        // Extract frame context (strip project name prefix if present)
        var context = currentFrameTitle
        if let ft = context, ft.hasPrefix(name + " \u{2013} ") {
            context = String(
                ft.dropFirst(name.count + 3)
            )
        }

        projects.append(JetBrainsProject(
            name: name,
            path: path,
            ideName: tool?.displayName ?? ideInfo.displayName,
            ideTag: ideInfo.tag,
            productCode: currentProductCode ?? "",
            lastOpened: date,
            frameTitle: context,
            isOpen: currentIsOpen,
            appPath: tool?.installLocation,
            launchCommand: tool?.launchCommand
        ))
    }

    private func expandUserHome(_ path: String) -> String {
        path.replacingOccurrences(
            of: "$USER_HOME$", with: homeDir
        )
    }
}
