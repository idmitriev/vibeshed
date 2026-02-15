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
        self.pickerCoordinator = PickerCoordinator(
            pickerState: pickerState,
            moduleRegistry: moduleRegistry,
            panelController: panelController,
            eventBus: eventBus
        )
        pickerCoordinator.usageTracker = usageTracker
        panelController.coordinator = pickerCoordinator

        // keyComboManager and uriManager need panelController, so we init them after
        let panel = panelController
        let picker = pickerState
        self.keyComboManager = KeyComboManager(
            eventBus: eventBus,
            configManager: configManager,
            moduleRegistry: moduleRegistry,
            permissionsManager: permissionsManager,
            togglePicker: { panel.toggle() }
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
            togglePicker: { panel.toggle() }
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
        moduleRegistry.startListeningForConfigChanges()
        permissionsManager.checkAll()
        logPermissionStatus()
        permissionsManager.startPeriodicRecheck()
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
        let bundleID = Bundle.main.bundleIdentifier ?? "com.vibeshed"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != currentPID }

        guard let existing = others.first else { return true }

        Log.app.warning(
            "Another Vibeshed instance already running (PID \(existing.processIdentifier)). Terminating."
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
            await registerModule(FavouritesModule())
            await registerModule(SystemModule())
            await registerModule(AudioModule())
            await registerModule(ClipboardModule())
            promptBrowserAutomation()
            await registerModule(BrowserModule())
            await registerModule(SpotifyModule())
            await registerModule(GitHubModule())
            await registerModule(VSCodeModule())
            await registerModule(ITermModule())
            await registerModule(AIModule())
            await registerModule(TelegramModule())
            showPermissionAlertIfNeeded()
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
                Log.stderr("  ⚠ automation: System Events — \(error[NSAppleScript.errorMessage] ?? "denied")")
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
            Log.app.error("Failed to register \(id) module: \(error.localizedDescription)")
            return
        }
        // register() returns without throwing when blocked by permissions — check if actually loaded
        if moduleRegistry.permissionErrors[id] != nil {
            let missing = moduleRegistry.permissionErrors[id]!.grantInstructions.joined(separator: ", ")
            Log.stderr("  ⚠ module: \(id) — waiting for permissions (\(missing))")
        } else if moduleRegistry.configErrors[id] != nil {
            Log.stderr("  ✗ module: \(id) — config error: \(moduleRegistry.configErrors[id]!)")
        } else {
            Log.stderr("  ✓ module: \(id)")
        }
    }

    private func logPermissionStatus() {
        for permission in Permission.allCases {
            let granted = permissionsManager.isGranted(permission)
            let mark = granted ? "✓" : "✗"
            Log.stderr("  \(mark) permission: \(permission.displayName)")
        }
    }

    private func showPermissionAlertIfNeeded() {
        let pending = moduleRegistry.permissionErrors
        guard !pending.isEmpty else { return }

        var lines: [String] = []
        for (moduleID, error) in pending.sorted(by: { $0.key < $1.key }) {
            lines.append("• \(moduleID)")
            for instruction in error.grantInstructions {
                lines.append("  \(instruction)")
            }
        }

        let message = lines.joined(separator: "\n")
        Log.stderr("⚠ Modules blocked by missing permissions:\n\(message)")

        let alert = NSAlert()
        alert.messageText = "Missing Permissions"
        alert.informativeText = """
            Some modules could not load due to missing permissions. \
            Grant the permissions below and they will activate automatically.

            \(message)
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Open the first missing permission's settings pane
            if case .denied(_, let permissions) = pending.values.first {
                if let url = permissions.first?.systemSettingsURL {
                    NSWorkspace.shared.open(url)
                }
            }
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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController.show()
        return false
    }
}
