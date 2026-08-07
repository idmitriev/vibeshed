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

        // Each section is decoded independently: a bad section falls back to its
        // default (with an error log) instead of discarding the whole file.
        config.keybindings = decodeSection(
            "keybindings", from: rootMapping, decoder: decoder
        ) ?? config.keybindings
        config.appearance = decodeSection(
            "appearance", from: rootMapping, decoder: decoder
        ) ?? config.appearance
        config.urlRouting = decodeSection(
            "urlRouting", from: rootMapping, decoder: decoder
        ) ?? config.urlRouting
        config.layoutCorrection = decodeSection(
            "layoutCorrection", from: rootMapping, decoder: decoder
        ) ?? config.layoutCorrection
        config.aliases = decodeSection(
            "aliases", from: rootMapping, decoder: decoder
        ) ?? config.aliases

        if let modulesNode = rootMapping[Node("modules")],
           let modulesMapping = modulesNode.mapping
        {
            for (keyNode, valueNode) in modulesMapping {
                guard let key = keyNode.string else { continue }
                do {
                    let moduleYAML = try Yams.serialize(node: valueNode)
                    config.moduleConfigs[key] = Data(moduleYAML.utf8)
                } catch {
                    let desc = error.localizedDescription
                    Log.config.error(
                        "Bad 'modules.\(key, privacy: .public)' section, skipping: \(desc, privacy: .public)"
                    )
                }
            }
        }

        return config
    }

    private static func decodeSection<T: Decodable>(
        _ key: String,
        from mapping: Yams.Node.Mapping,
        decoder: YAMLDecoder
    ) -> T? {
        guard let node = mapping[Node(key)] else { return nil }
        do {
            let yaml = try Yams.serialize(node: node)
            return try decoder.decode(T.self, from: yaml)
        } catch {
            let desc = error.localizedDescription
            Log.config.error(
                "Ignoring invalid '\(key, privacy: .public)' section, using defaults: \(desc, privacy: .public)"
            )
            return nil
        }
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
