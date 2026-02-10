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

    private var querySubscription: Any?

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

        configManager.start()
        moduleRegistry.startListeningForConfigChanges()
        permissionsManager.checkAll()
        permissionsManager.startPeriodicRecheck()
        wireQueryToModules()
        keyComboManager.startListening()
        keyComboManager.applyBindings(configManager.config.keybindings)
        uriManager.start()

        if isUITesting {
            setupUITesting()
        } else {
            registerModules()
        }

        Log.app.info("Vibeshed launched")
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
            let windowModule = WindowModule()
            do {
                try await moduleRegistry.register(windowModule)
            } catch {
                Log.app.error("Failed to register window module: \(error.localizedDescription)")
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

    private func wireQueryToModules() {
        querySubscription = pickerState.debouncedQuery
            .sink { [weak self] query in
                guard let self else { return }
                pickerState.isLoading = true
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let scoring = ScoringContext(
                        usageCounts: [:],
                        lastUsedDates: [:],
                        query: query
                    )
                    let results = await moduleRegistry.queryAll(
                        query: query,
                        scoring: scoring
                    )
                    pickerState.actions = results.map { action in
                        ActionItem(
                            id: action.id,
                            title: action.title,
                            subtitle: action.subtitle,
                            iconSystemName: action.iconName,
                            score: action.relevanceScore,
                            moduleID: String(action.id.rawValue.prefix(while: { $0 != "." }))
                        )
                    }
                    if !pickerState.actions.isEmpty {
                        pickerState.selectedActionID = pickerState.actions.first?.id
                    }
                    pickerState.isLoading = false
                }
            }
    }
}
