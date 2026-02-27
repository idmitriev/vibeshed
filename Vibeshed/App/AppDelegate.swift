import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let eventBus: EventBus
    let configManager: ConfigManager
    let permissionsManager: PermissionsManager
    let pickerState: PickerState
    let panelController: PanelController
    let moduleRegistry: ModuleRegistry
    let keyComboManager: KeyComboManager
    let uriManager: URIManager
    let usageTracker: UsageTracker
    let pickerCoordinator: PickerCoordinator
    let themeEngine: ThemeEngine
    let autostartManager: AutostartManager
    let aliasManager: AliasManager

    override init() {
        self.eventBus = EventBus()
        self.configManager = ConfigManager(eventBus: eventBus)
        self.permissionsManager = PermissionsManager(eventBus: eventBus)
        self.pickerState = PickerState()
        self.panelController = PanelController(pickerState: pickerState)
        self.moduleRegistry = ModuleRegistry(
            eventBus: eventBus,
            configManager: configManager,
            permissionsManager: permissionsManager
        )
        self.usageTracker = UsageTracker()
        self.themeEngine = ThemeEngine(eventBus: eventBus)
        self.autostartManager = AutostartManager()
        self.pickerCoordinator = PickerCoordinator(
            pickerState: pickerState,
            moduleRegistry: moduleRegistry,
            panelController: panelController,
            eventBus: eventBus
        )
        self.aliasManager = AliasManager(configManager: configManager, eventBus: eventBus)
        pickerCoordinator.usageTracker = usageTracker
        pickerCoordinator.themeEngine = themeEngine
        pickerCoordinator.aliasManager = aliasManager
        moduleRegistry.aliasManager = aliasManager
        panelController.coordinator = pickerCoordinator
        panelController.themeEngine = themeEngine

        // keyComboManager and uriManager need panelController, so we init them after
        let panel = panelController
        let picker = pickerState
        let coordinator = pickerCoordinator
        self.keyComboManager = KeyComboManager(
            eventBus: eventBus,
            configManager: configManager,
            moduleRegistry: moduleRegistry,
            permissionsManager: permissionsManager,
            togglePicker: { panel.toggle() },
            showParameterInput: { action in
                coordinator.showForParameterInput(action: action)
            }
        )
        self.uriManager = URIManager(
            eventBus: eventBus,
            configManager: configManager,
            moduleRegistry: moduleRegistry,
            showPicker: { query in
                panel.show()
                if let query {
                    picker.query = query
                }
            },
            togglePicker: { panel.toggle() },
            showURLChooser: { _, actions in
                panel.show()
                picker.query = ""
                let items = actions.map { action in
                    ActionItem(
                        id: action.id,
                        title: action.title,
                        subtitle: action.subtitle,
                        iconSystemName: action.iconName,
                        score: action.relevanceScore,
                        moduleID: "url",
                        hasParameters: false,
                        keywords: action.keywords
                    )
                }
                var cache: [ActionID: any Action] = [:]
                for action in actions {
                    cache[action.id] = action
                }
                picker.pushMode(.pushedActions)
                picker.updateActions(items, cache: cache)
            }
        )
        super.init()
    }

    var isUITesting: Bool {
        CommandLine.arguments.contains("--ui-testing")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ensureSingleInstance() else { return }

        Log.stderr("Vibeshed starting…")
        configManager.start()
        aliasManager.start()
        moduleRegistry.startListeningForConfigChanges()
        permissionsManager.checkAll()
        logPermissionStatus()
        permissionsManager.startPeriodicRecheck()
        // Prompt for Accessibility + Input Monitoring so the app is
        // registered in System Settings and the user can grant them.
        permissionsManager.request(.accessibility)
        permissionsManager.request(.inputMonitoring)
        themeEngine.start(
            intensity: configManager.config.appearance.themeIntensity
        )
        pickerCoordinator.start()
        keyComboManager.startListening()
        keyComboManager.applyBindings(configManager.config.keybindings)
        uriManager.start()

        if isUITesting {
            setupUITesting()
        } else {
            registerModules()
        }

        Log.app.info("Vibeshed launched")
        Log.stderr("Vibeshed launched (use ⌘Q in menu bar to quit)")
    }

    /// Returns `true` if this is the only running instance, `false` if another instance was found and activated.
    private func ensureSingleInstance() -> Bool {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let bundleID = Bundle.main.bundleIdentifier ?? "com.ivandmitriev.Vibeshed"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != currentPID }

        guard let existing = others.first else { return true }

        Log.app.warning(
            "Another Vibeshed instance already running (PID \(existing.processIdentifier, privacy: .public)). Terminating."
        )
        existing.activate()
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
        return false
    }

    private func registerModules() {
        Task { @MainActor in
            await registerModule(WindowModule())
            await registerModule(ApplicationModule())
            await registerModule(SystemModule())
            await registerModule(buildSelfModule())
            await registerModule(AudioModule())
            await registerModule(ClipboardModule())
            promptBrowserAutomation()
            await registerModule(BrowserModule())
            await registerModule(SpotifyModule())
            await registerModule(GitHubModule())
            await registerModule(VSCodeModule())
            await registerModule(JetBrainsModule())
            await registerModule(ITermModule())
            await registerModule(AIModule())
            await registerModule(TelegramModule())
            await registerModule(ZoomModule())
            await registerModule(CalendarModule())
        }
    }

    /// Trigger the macOS automation consent dialog via NSAppleScript.
    /// First probes System Events, then each running browser.
    /// NSAppleScript runs in-process which is required for TCC to register the app properly.
    private func promptBrowserAutomation() {
        // First, request System Events automation (triggers TCC registration)
        let systemEventsScript = """
            tell application "System Events"
                return name of first process
            end tell
            """
        if let script = NSAppleScript(source: systemEventsScript) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            if let error {
                Log.stderr(
                    "  ⚠ automation: System Events — \(error[NSAppleScript.errorMessage] ?? "denied")"
                )
            } else {
                Log.stderr("  ✓ automation: System Events")
            }
        }

        // Then probe each running browser
        for entry in BrowserRegistry.appleScriptCapable {
            let name = entry.name
            let bundleID = entry.bundleID
            guard BrowserRegistry.isRunning(bundleID) else { continue }

            let browserScript = """
                tell application id "\(bundleID)"
                    return name
                end tell
                """
            if let script = NSAppleScript(source: browserScript) {
                var error: NSDictionary?
                script.executeAndReturnError(&error)
                if let error {
                    Log.stderr(
                        "  ⚠ automation: \(name) — \(error[NSAppleScript.errorMessage] ?? "denied")"
                    )
                } else {
                    Log.stderr("  ✓ automation: \(name)")
                }
            }
        }
    }

    private func registerModule(_ module: any Module) async {
        let id = await module.id
        do {
            try await moduleRegistry.register(module)
        } catch {
            Log.stderr("  ✗ module: \(id) — \(error.localizedDescription)")
            Log.app.error(
                "Failed to register \(id, privacy: .public) module: \(error.localizedDescription, privacy: .public)"
            )
            return
        }
        // register() returns without throwing when blocked by permissions — check if actually loaded
        if moduleRegistry.permissionErrors[id] != nil {
            let missing = moduleRegistry.permissionErrors[id]!.grantInstructions.joined(
                separator: ", ")
            Log.stderr("  ⚠ module: \(id) — waiting for permissions (\(missing))")
        } else if moduleRegistry.configErrors[id] != nil {
            Log.stderr("  ✗ module: \(id) — config error: \(moduleRegistry.configErrors[id]!)")
        } else {
            Log.stderr("  ✓ module: \(id)")
        }
    }

    private func buildSelfModule() -> SelfModule {
        let cfgManager = configManager
        let registry = moduleRegistry

        return SelfModule(
            configFileURL: cfgManager.configFileURL,
            configDirURL: cfgManager.configDirectoryURL,
            reloadConfig: { @MainActor in
                cfgManager.reload()
            },
            getModuleStatus: { @MainActor in
                var entries: [ModuleStatusInfo.Entry] = []
                for id in registry.moduleIDs {
                    entries.append(.init(id: id, status: .loaded, message: nil))
                }
                for (id, msg) in registry.configErrors {
                    entries.append(
                        .init(
                            id: id, status: .configError, message: msg
                        ))
                }
                for (id, err) in registry.permissionErrors {
                    entries.append(
                        .init(
                            id: id,
                            status: .permissionError,
                            message: err.localizedDescription
                        ))
                }
                return ModuleStatusInfo(
                    entries: entries.sorted { $0.id < $1.id }
                )
            }
        )
    }

    private func logPermissionStatus() {
        for permission in Permission.allCases {
            let granted = permissionsManager.isGranted(permission)
            let mark = granted ? "✓" : "✗"
            Log.stderr("  \(mark) permission: \(permission.displayName)")
        }
    }

    private func setupUITesting() {
        Task { @MainActor in
            let mockModule = MockModule()
            try await moduleRegistry.register(mockModule)
            panelController.show()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        uriManager.handleURLs(urls)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
        -> Bool {
        panelController.show()
        return false
    }
}
