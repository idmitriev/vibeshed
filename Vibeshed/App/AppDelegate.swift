import AppKit
import SwiftUI
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let togglePicker = Self("togglePicker", default: .init(.space, modifiers: [.option]))
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var panelController: PanelController!
    private(set) var pickerState: PickerState!
    private(set) var eventBus: EventBus!
    private(set) var configManager: ConfigManager!
    private(set) var permissionsManager: PermissionsManager!
    private(set) var moduleRegistry: ModuleRegistry!

    private var querySubscription: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        eventBus = EventBus()
        configManager = ConfigManager(eventBus: eventBus)
        configManager.start()

        permissionsManager = PermissionsManager()
        permissionsManager.checkPermissions()

        pickerState = PickerState()
        panelController = PanelController(pickerState: pickerState)

        moduleRegistry = ModuleRegistry(eventBus: eventBus)

        wireQueryToModules()

        KeyboardShortcuts.onKeyUp(for: .togglePicker) { [weak self] in
            self?.panelController.toggle()
        }

        Log.app.info("Vibeshed launched")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController.show()
        return false
    }

    private func wireQueryToModules() {
        querySubscription = pickerState.debouncedQuery
            .sink { [weak self] query in
                guard let self else { return }
                self.pickerState.isLoading = true
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let scoring = ScoringContext(
                        usageCounts: [:],
                        lastUsedDates: [:],
                        query: query
                    )
                    let results = await self.moduleRegistry.queryAll(
                        query: query,
                        scoring: scoring
                    )
                    self.pickerState.actions = results.map { action in
                        ActionItem(
                            id: action.id,
                            title: action.title,
                            subtitle: action.subtitle,
                            iconSystemName: action.iconName,
                            score: action.relevanceScore,
                            moduleID: String(action.id.rawValue.prefix(while: { $0 != "." }))
                        )
                    }
                    if !self.pickerState.actions.isEmpty {
                        self.pickerState.selectedActionID = self.pickerState.actions.first?.id
                    }
                    self.pickerState.isLoading = false
                }
            }
    }
}
