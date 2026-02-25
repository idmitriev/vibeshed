import Foundation
import Yams

@MainActor
@Observable
final class ConfigManager {
    private(set) var config: AppConfig = .init()

    let configDirectoryURL: URL
    let configFileURL: URL
    private let eventBus: EventBus
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    init(eventBus: EventBus) {
        self.eventBus = eventBus
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.configDirectoryURL = home.appendingPathComponent(".config/vibeshed")
        self.configFileURL = configDirectoryURL.appendingPathComponent("config.yaml")
    }

    func start() {
        ensureConfigDirectory()
        loadConfig()
        startMonitoring()
    }

    func stop() {
        fileMonitor?.cancel()
        if fileDescriptor >= 0 { close(fileDescriptor) }
    }

    private func ensureConfigDirectory() {
        try? FileManager.default.createDirectory(
            at: configDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    func reload() {
        loadConfig()
    }

    private func loadConfig() {
        guard FileManager.default.fileExists(atPath: configFileURL.path) else {
            Log.config.info("No config file at \(self.configFileURL.path, privacy: .public), using defaults")
            return
        }
        do {
            let yamlString = try String(contentsOf: configFileURL, encoding: .utf8)
            let decoded = try Self.parseYAML(yamlString)
            guard decoded != config else {
                Log.config.debug("Config unchanged, skipping reload")
                return
            }
            config = decoded
            Log.config.info("Config loaded successfully")
            Task { await eventBus.publish(.configReloaded) }
        } catch {
            Log.config.error("Failed to load config: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func parseYAML(_ yamlString: String) throws -> AppConfig {
        guard let rootNode = try Yams.compose(yaml: yamlString),
              let rootMapping = rootNode.mapping
        else {
            return AppConfig()
        }

        var config = AppConfig()
        let decoder = YAMLDecoder()

        if let keybindingsNode = rootMapping[Node("keybindings")] {
            let keybindingsYAML = try Yams.serialize(node: keybindingsNode)
            config.keybindings = try decoder.decode(
                [KeyBindingEntry].self,
                from: keybindingsYAML
            )
        }

        if let appearanceNode = rootMapping[Node("appearance")] {
            let appearanceYAML = try Yams.serialize(node: appearanceNode)
            config.appearance = try decoder.decode(
                AppConfig.AppearanceConfig.self,
                from: appearanceYAML
            )
        }

        if let modulesNode = rootMapping[Node("modules")],
           let modulesMapping = modulesNode.mapping {
            for (keyNode, valueNode) in modulesMapping {
                if let key = keyNode.string {
                    let moduleYAML = try Yams.serialize(node: valueNode)
                    config.moduleConfigs[key] = Data(moduleYAML.utf8)
                }
            }
        }

        if let urlRoutingNode = rootMapping[Node("urlRouting")] {
            let urlRoutingYAML = try Yams.serialize(node: urlRoutingNode)
            config.urlRouting = try decoder.decode(
                URLRoutingConfig.self,
                from: urlRoutingYAML
            )
        }

        if let keyRemapsNode = rootMapping[Node("keyRemaps")] ?? rootMapping[Node("appRemaps")] {
            let keyRemapsYAML = try Yams.serialize(node: keyRemapsNode)
            config.keyRemaps = try decoder.decode(
                [KeyRemapGroup].self,
                from: keyRemapsYAML
            )
        }

        if let mouseRemapsNode = rootMapping[Node("mouseRemaps")] {
            let mouseRemapsYAML = try Yams.serialize(node: mouseRemapsNode)
            config.mouseRemaps = try decoder.decode(
                [MouseRemapEntry].self,
                from: mouseRemapsYAML
            )
        }

        if let aliasesNode = rootMapping[Node("aliases")] {
            let aliasesYAML = try Yams.serialize(node: aliasesNode)
            config.aliases = try decoder.decode(
                [AliasEntry].self,
                from: aliasesYAML
            )
        }

        return config
    }

    private func startMonitoring() {
        let fd = open(configFileURL.path, O_EVTONLY)
        guard fd >= 0 else {
            Log.config.warning("Cannot monitor config file (open failed)")
            return
        }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.loadConfig()
        }

        source.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                Darwin.close(fd)
                self?.fileDescriptor = -1
            }
        }

        source.resume()
        fileMonitor = source
    }
}
