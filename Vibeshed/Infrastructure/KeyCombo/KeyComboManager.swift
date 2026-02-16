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
    private var capsLockMonitorRunning = false

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
                case .permissionChanged(let permission, let granted):
                    self.handlePermissionChanged(
                        permission: permission, granted: granted
                    )
                case .moduleRegistered:
                    self.validateBindings()
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
        if capsLockMonitorRunning {
            CapsLockMonitor.shared.stop()
            capsLockMonitorRunning = false
        }
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

    private func handlePermissionChanged(
        permission: Permission, granted: Bool
    ) {
        switch permission {
        case .accessibility:
            // Retry event tap when accessibility changes — the
            // preflight APIs are unreliable for ad-hoc signed apps,
            // so we just attempt to create the tap again.
            if !eventTapRunning, needsEventTap() {
                rebindAll()
            }
        case .inputMonitoring:
            if eventTapRunning {
                let hasCaps = currentEntries.contains { entry in
                    if let ct = try? KeyComboParser.parse(entry.combo),
                       case .capsLockModifier = ct
                    {
                        return true
                    }
                    return false
                }
                manageCapsLockMonitor(hasCapsLockBindings: hasCaps)
            }
        default:
            break
        }
    }

    private func validateBindings() {
        for entry in currentEntries {
            let actionID = ActionID(entry.action)
            guard actionID.rawValue != "app.togglePicker" else { continue }

            let moduleID = String(actionID.rawValue.prefix(while: { $0 != "." }))
            // Only warn if the module is registered but the action doesn't exist
            guard moduleRegistry.module(id: moduleID) != nil else { continue }

            Task { [weak self] in
                guard let self else { return }
                if await moduleRegistry.findAction(id: actionID) == nil {
                    bindingErrors[entry.combo] = "Action '\(entry.action)' not found in module '\(moduleID)'"
                    Log.keybindings.warning(
                        "Action '\(entry.action, privacy: .public)' for combo '\(entry.combo, privacy: .public)' not available"
                    )
                } else {
                    bindingErrors.removeValue(forKey: entry.combo)
                }
            }
        }
    }

    private func rebindAll() {
        // Stop existing tap and CapsLockMonitor
        if eventTapRunning {
            eventTapHandler.stop()
            eventTapRunning = false
        }
        if capsLockMonitorRunning {
            CapsLockMonitor.shared.stop()
            capsLockMonitorRunning = false
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

        // Try to create the event tap (needs Accessibility permission).
        // We skip preflight checks — CGEvent.tapCreate is the real test.
        guard eventTapHandler.start() else {
            let message =
                "Event tap failed — grant Accessibility permission"
            for entry in currentEntries where bindingErrors[entry.combo] == nil {
                bindingErrors[entry.combo] = message
            }
            return
        }
        eventTapRunning = true
        Log.keybindings.info(
            "Applied \(totalBindings, privacy: .public) keybinding(s)"
        )

        // CapsLockMonitor needs Input Monitoring — manage separately
        manageCapsLockMonitor(hasCapsLockBindings: !capsLock.isEmpty)
    }

    private func needsEventTap() -> Bool {
        currentEntries.contains { entry in
            (try? KeyComboParser.parse(entry.combo)) != nil
        }
    }

    private func manageCapsLockMonitor(hasCapsLockBindings: Bool) {
        if hasCapsLockBindings {
            if permissionsManager.isGranted(.inputMonitoring) {
                if !capsLockMonitorRunning {
                    CapsLockMonitor.shared.start()
                    capsLockMonitorRunning = true
                }
            } else {
                let msg =
                    "CapsLock combos need Input Monitoring permission"
                Log.keybindings.warning("\(msg, privacy: .public)")
                for entry in currentEntries {
                    if let ct = try? KeyComboParser.parse(entry.combo),
                       case .capsLockModifier = ct
                    {
                        bindingErrors[entry.combo] = msg
                    }
                }
                if capsLockMonitorRunning {
                    CapsLockMonitor.shared.stop()
                    capsLockMonitorRunning = false
                }
            }
        } else if capsLockMonitorRunning {
            CapsLockMonitor.shared.stop()
            capsLockMonitorRunning = false
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
