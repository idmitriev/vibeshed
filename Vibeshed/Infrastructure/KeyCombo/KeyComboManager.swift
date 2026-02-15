import Foundation

@MainActor
@Observable
final class KeyComboManager {
    private(set) var bindingErrors: [String: String] = [:]

    private let eventBus: EventBus
    private let configManager: ConfigManager
    private let moduleRegistry: ModuleRegistry
    private let permissionsManager: PermissionsManager
    private let togglePicker: () -> Void

    private let eventTapHandler: EventTapHandler
    private var currentEntries: [KeyBindingEntry] = []
    private var eventTapRunning = false

    init(
        eventBus: EventBus,
        configManager: ConfigManager,
        moduleRegistry: ModuleRegistry,
        permissionsManager: PermissionsManager,
        togglePicker: @escaping () -> Void
    ) {
        self.eventBus = eventBus
        self.configManager = configManager
        self.moduleRegistry = moduleRegistry
        self.permissionsManager = permissionsManager
        self.togglePicker = togglePicker
        self.eventTapHandler = EventTapHandler { [weak moduleRegistry, weak eventBus, togglePicker] actionID in
            Task { @MainActor in
                // Built-in actions
                if actionID.rawValue == "app.togglePicker" {
                    togglePicker()
                    return
                }

                guard let moduleRegistry, let eventBus else { return }
                await Self.executeAction(
                    actionID,
                    moduleRegistry: moduleRegistry,
                    eventBus: eventBus
                )
            }
        }
    }

    // MARK: - Public

    func startListening() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let (_, stream) = await eventBus.subscribe()
            for await event in stream {
                switch event {
                case .configReloaded:
                    self.handleConfigReloaded()
                case .permissionChanged:
                    self.handlePermissionChanged()
                case .moduleRegistered:
                    self.revalidateWarnings()
                default:
                    break
                }
            }
        }
    }

    func applyBindings(_ entries: [KeyBindingEntry]) {
        currentEntries = entries
        rebindAll()
    }

    func stop() {
        eventTapHandler.stop()
        eventTapRunning = false
        currentEntries = []
        bindingErrors = [:]
    }

    // MARK: - Private

    private func handleConfigReloaded() {
        let newEntries = configManager.config.keybindings
        guard newEntries != currentEntries else { return }
        currentEntries = newEntries
        rebindAll()
    }

    private func handlePermissionChanged() {
        // If we have bindings that need the event tap but it wasn't running, retry
        if !eventTapRunning, needsEventTap() {
            rebindAll()
        }
    }

    private func revalidateWarnings() {
        // On module registration, re-validate action IDs that had warnings
        for (combo, _) in bindingErrors {
            // Clear errors for actions that are now findable
            if let entry = currentEntries.first(where: { $0.combo == combo }) {
                let actionID = ActionID(entry.action)
                Task {
                    if await moduleRegistry.findAction(id: actionID) != nil {
                        bindingErrors.removeValue(forKey: combo)
                    }
                }
            }
        }
    }

    private func rebindAll() {
        // Stop existing tap
        if eventTapRunning {
            eventTapHandler.stop()
            eventTapRunning = false
        }

        bindingErrors = [:]

        // Parse all entries
        var standard: [ResolvedBinding] = []
        var capsLock: [ResolvedBinding] = []
        var space: [ResolvedBinding] = []
        var mouse: [ResolvedBinding] = []
        var seenCombos: Set<String> = []

        for entry in currentEntries {
            let comboKey = entry.combo.lowercased()
            if seenCombos.contains(comboKey) {
                bindingErrors[entry.combo] = KeyComboError.duplicateBinding(entry.combo).localizedDescription
                Task { await eventBus.publish(.keybindingError(combo: entry.combo, message: bindingErrors[entry.combo]!)) }
                continue
            }
            seenCombos.insert(comboKey)

            do {
                let comboType = try KeyComboParser.parse(entry.combo)
                let binding = ResolvedBinding(
                    comboType: comboType,
                    actionID: ActionID(entry.action),
                    rawCombo: entry.combo
                )

                switch comboType {
                case .standard:
                    standard.append(binding)
                case .capsLockModifier:
                    capsLock.append(binding)
                case .spaceModifier:
                    space.append(binding)
                case .mouseButton:
                    mouse.append(binding)
                }

                // Soft-validate action existence (warning only)
                let actionID = ActionID(entry.action)
                if actionID.rawValue != "app.togglePicker" {
                    Task { [weak self] in
                        guard let self else { return }
                        if await moduleRegistry.findAction(id: actionID) == nil {
                            Log.keybindings.warning(
                                "Action '\(entry.action, privacy: .public)' for combo '\(entry.combo, privacy: .public)' not currently available"
                            )
                        }
                    }
                }
            } catch {
                let message = error.localizedDescription
                bindingErrors[entry.combo] = message
                Log.keybindings.error("Invalid keybinding '\(entry.combo, privacy: .public)': \(message, privacy: .public)")
                Task { await eventBus.publish(.keybindingError(combo: entry.combo, message: message)) }
            }
        }

        // Update bindings on the handler (thread-safe)
        eventTapHandler.updateBindings(
            standard: standard,
            capsLock: capsLock,
            space: space,
            mouse: mouse
        )

        // Start event tap if we have any bindings
        let totalBindings = standard.count + capsLock.count + space.count + mouse.count
        guard totalBindings > 0 else {
            Log.keybindings.info("No keybindings configured")
            return
        }

        // Check permissions
        let required: Set<Permission> = [.accessibility, .inputMonitoring]
        let missing = permissionsManager.missingPermissions(from: required)
        if !missing.isEmpty {
            let names = missing.map(\.displayName).sorted().joined(separator: ", ")
            let message = "Event tap requires permissions: \(names)"
            Log.keybindings.error("Event tap requires permissions: \(names, privacy: .public)")
            // Mark all bindings as errored due to permissions
            for entry in currentEntries where bindingErrors[entry.combo] == nil {
                bindingErrors[entry.combo] = message
            }
            return
        }

        eventTapHandler.start()
        eventTapRunning = true
        Log.keybindings.info("Applied \(totalBindings, privacy: .public) keybinding(s)")
    }

    private func needsEventTap() -> Bool {
        currentEntries.contains { entry in
            (try? KeyComboParser.parse(entry.combo)) != nil
        }
    }

    // MARK: - Action Execution

    private static func executeAction(
        _ actionID: ActionID,
        moduleRegistry: ModuleRegistry,
        eventBus: EventBus
    ) async {
        guard let action = await moduleRegistry.findAction(id: actionID) else {
            Log.keybindings.error("Action not found: \(actionID, privacy: .public)")
            await eventBus.publish(.actionFailed(actionID, message: "Action not found"))
            return
        }

        let moduleID = String(actionID.rawValue.prefix(while: { $0 != "." }))
        do {
            _ = try await action.run(with: [:])
            await eventBus.publish(.actionExecuted(actionID, moduleID: moduleID))
        } catch {
            Log.keybindings.error("Action \(actionID, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            await eventBus.publish(.actionFailed(actionID, message: error.localizedDescription))
        }
    }
}
