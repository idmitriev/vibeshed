import AppKit
import ShowreelCore

extension SceneRunner {
    private var configDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/vibeshed")
    }

    /// Writes the scene's config and state files, then relaunches Vibeshed so
    /// it starts from them.
    func setUpVibeshed(_ setup: VibeshedSetup) async throws {
        guard setup.launch || !setup.config.isEmpty || !setup.files.isEmpty else { return }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: Windows.vibeshedBundleID)
        if setup.launch {
            for app in running {
                await Apps.quit(app, timeout: 1.5)
            }
        }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        if !setup.config.isEmpty {
            try backUpUserConfig()
            let texts = try setup.config.map { try String(contentsOf: resolve($0), encoding: .utf8) }
            let merged = try ConfigMerge.merge(texts, secrets: secrets())
            let destination = configDirectory.appendingPathComponent("config.yaml")
            try merged.write(to: destination, atomically: true, encoding: .utf8)
        }
        if setup.reset {
            for name in ["usage.json", "clipboard.json", "timers.json"] {
                try? fileManager.removeItem(at: configDirectory.appendingPathComponent(name))
            }
            // The last applied palette theme tints the picker on the next launch.
            try Shell.capture(["/usr/bin/defaults", "delete", Windows.vibeshedBundleID, "theme.active"], check: false)
        }
        for (name, source) in setup.files.sorted(by: { $0.key < $1.key }) {
            try replace(configDirectory.appendingPathComponent(name), with: resolve(source))
        }
        guard setup.launch else { return }
        try await launchVibeshed(setup)
    }

    private func launchVibeshed(_ setup: VibeshedSetup) async throws {
        let appURL = setup.appURL
        guard FileManager.default.fileExists(atPath: appURL.path) else {
            throw AgentError("no Vibeshed at \(setup.app) — run `scripts/showreel vm install-vibeshed`")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        let app = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        Log.info("launched Vibeshed \(Bundle(url: appURL)?.shortVersion ?? "") (pid \(app.processIdentifier))")
        guard await waitForStatusItem(of: app, timeout: 15) else {
            throw AgentError("Vibeshed didn't finish launching — is Accessibility granted to it in the VM?")
        }
        // Modules load and fetch their catalogs right after the status item appears.
        try await Task.sleep(for: .seconds(1.5))
        if setup.warmUp {
            try await warmUpPicker()
        }
        if setup.keystrokes {
            try await open("vibeshed://self/toggleKeystrokeVisualizer")
        }
    }

    private func warmUpPicker() async throws {
        try await open("vibeshed://picker")
        try await waitFor(WaitCondition(window: .picker))
        try await Task.sleep(for: .seconds(1.5))
        try await Keyboard.tap(.parse("escape"))
        do {
            try await waitFor(WaitCondition(window: .picker, gone: true, timeout: 1.5))
        } catch {
            // Escape doesn't always reach a picker opened by URL right after
            // launch; a click outside it (on the backdrop or the desktop) closes it.
            let corner = Point(x: manifest.display.width - 60, y: manifest.display.height - 60)
            try await Mouse.click(Click(at: corner, glide: 0))
            try await waitFor(WaitCondition(window: .picker, gone: true, timeout: 3))
        }
        try await Task.sleep(for: .seconds(0.3))
        Log.info("warmed up the picker")
    }

    /// The menu bar extra shows up once Vibeshed's app delegate has run.
    private func waitForStatusItem(of app: NSRunningApplication, timeout: Double) async -> Bool {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !app.isTerminated {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &value) == .success {
                return true
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    /// `~/Showreel/secrets.env`, copied from the host's showreel/.vm/secrets.env.
    private func secrets() -> [String: String] {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Showreel/secrets.env")
        return (try? String(contentsOf: url, encoding: .utf8)).map(ConfigMerge.parseEnv) ?? [:]
    }

    /// Keeps the guest's own config the first time a scene replaces it.
    private func backUpUserConfig() throws {
        let config = configDirectory.appendingPathComponent("config.yaml")
        let backup = configDirectory.appendingPathComponent("config.yaml.before-showreel")
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: config.path), !fileManager.fileExists(atPath: backup.path) {
            try fileManager.copyItem(at: config, to: backup)
            Log.info("backed up the VM's config to \(backup.path)")
        }
    }

    private func replace(_ destination: URL, with source: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else { throw AgentError("no file at \(source.path)") }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
    }
}

extension VibeshedSetup {
    /// `app`, with `~` expanded.
    var appURL: URL {
        URL(fileURLWithPath: (app as NSString).expandingTildeInPath)
    }
}

extension Bundle {
    var shortVersion: String? {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
}
