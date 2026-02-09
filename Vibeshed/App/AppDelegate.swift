import AppKit
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let togglePicker = Self("togglePicker", default: .init(.space, modifiers: [.option]))
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let eventBus: EventBus
    let configManager: ConfigManager
    let permissionsManager: PermissionsManager
    let pickerState: PickerState
    let panelController: PanelController
    let moduleRegistry: ModuleRegistry

    private var querySubscription: Any?

    override init() {
        self.eventBus = EventBus()
        self.configManager = ConfigManager(eventBus: eventBus)
        self.permissionsManager = PermissionsManager()
        self.pickerState = PickerState()
        self.panelController = PanelController(pickerState: pickerState)
        self.moduleRegistry = ModuleRegistry(eventBus: eventBus, configManager: configManager)
        super.init()
    }

    var isUITesting: Bool {
        CommandLine.arguments.contains("--ui-testing")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configManager.start()
        moduleRegistry.startListeningForConfigChanges()
        permissionsManager.checkPermissions()
        wireQueryToModules()

        KeyboardShortcuts.onKeyUp(for: .togglePicker) { [weak self] in
            self?.panelController.toggle()
        }

        if isUITesting {
            setupUITesting()
        }

        Log.app.info("Vibeshed launched")
    }

    private func setupUITesting() {
        Task { @MainActor in
            let mockModule = MockModule()
            try await moduleRegistry.register(mockModule)
            panelController.show()
        }
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
