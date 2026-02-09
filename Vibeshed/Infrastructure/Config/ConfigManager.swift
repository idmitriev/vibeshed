import Foundation

@MainActor
@Observable
final class ConfigManager {
    private(set) var config: AppConfig = .init()

    private let configDirectoryURL: URL
    private let configFileURL: URL
    private let eventBus: EventBus
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    init(eventBus: EventBus) {
        self.eventBus = eventBus
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.configDirectoryURL = home.appendingPathComponent(".config/vibeshed")
        self.configFileURL = configDirectoryURL.appendingPathComponent("config.json")
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

    private func loadConfig() {
        guard FileManager.default.fileExists(atPath: configFileURL.path) else {
            Log.config.info("No config file at \(self.configFileURL.path), using defaults")
            return
        }
        do {
            let data = try Data(contentsOf: configFileURL)
            let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
            guard decoded != config else {
                Log.config.debug("Config unchanged, skipping reload")
                return
            }
            config = decoded
            Log.config.info("Config loaded successfully")
            Task { await eventBus.publish(.configReloaded) }
        } catch {
            Log.config.error("Failed to load config: \(error.localizedDescription)")
        }
    }

    private func startMonitoring() {
        let fd = open(configFileURL.path, O_EVTONLY)
        guard fd >= 0 else {
            Log.config.warning("Cannot monitor config file (open failed)")
            return
        }
        self.fileDescriptor = fd

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
        self.fileMonitor = source
    }
}
