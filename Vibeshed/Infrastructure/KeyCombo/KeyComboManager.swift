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
                Log.keybindings.info("Executing action: \(actionID.rawValue, privacy: .public)")
                // Built-in actions
                if actionID.rawValue == "app.togglePicker" {
                    Log.keybindings.debug("Toggling picker (built-in action)")
                    togglePicker()
                    return
                }

                guard let moduleRegistry, let eventBus else {
                    let aid = actionID.rawValue
                    Log.keybindings.error(
                        "Cannot execute \(aid, privacy: .public): deallocated"
                    )
                    return
                }
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
        Log.keybindings.info("applyBindings called with \(entries.count, privacy: .public) entries")
        for entry in entries {
            Log.keybindings.debug("  Config entry: '\(entry.combo, privacy: .public)' → '\(entry.action, privacy: .public)'")
        }
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
        guard newEntries != currentEntries else {
            Log.keybindings.debug("Config reloaded but keybindings unchanged")
            return
        }
        let oldCount = currentEntries.count
        Log.keybindings.info(
            "Config reloaded: \(newEntries.count, privacy: .public) keybindings (was \(oldCount, privacy: .public))"
        )
        currentEntries = newEntries
        rebindAll()
    }

    private func handlePermissionChanged(
        permission: Permission, granted: Bool
    ) {
        let status = granted ? "granted" : "denied"
        let name = permission.displayName
        let tapState = eventTapRunning
        Log.keybindings.info(
            "Permission changed: \(name, privacy: .public) → \(status, privacy: .public) (tapRunning=\(tapState, privacy: .public))"
        )
        switch permission {
        case .accessibility:
            // Retry event tap when accessibility changes — the
            // preflight APIs are unreliable for ad-hoc signed apps,
            // so we just attempt to create the tap again.
            if !eventTapRunning, needsEventTap() {
                Log.keybindings.info("Accessibility changed, retrying event tap")
                rebindAll()
            }
        case .inputMonitoring:
            if eventTapRunning {
                let hasCaps = currentEntries.contains { entry in
                    if let ct = try? KeyComboParser.parse(entry.combo),
                       case .capsLockModifier = ct {
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

    // swiftlint:disable:next function_body_length
    private func rebindAll() {
        let entryCount = currentEntries.count
        Log.keybindings.info("rebindAll: processing \(entryCount, privacy: .public) entries")

        // Stop existing tap and CapsLockMonitor
        if eventTapRunning {
            Log.keybindings.debug("rebindAll: stopping existing event tap")
            eventTapHandler.stop()
            eventTapRunning = false
        }
        if capsLockMonitorRunning {
            Log.keybindings.debug("rebindAll: stopping CapsLockMonitor")
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
                case .standard(let keyCode, let modifiers):
                    standard.append(binding)
                    let fl = modifiers.rawValue
                    Log.keybindings.debug(
                        "  Parsed '\(entry.combo, privacy: .public)': standard key=\(keyCode, privacy: .public) flags=\(fl, privacy: .public)"
                    )
                case .capsLockModifier(let keyCode):
                    capsLock.append(binding)
                    Log.keybindings.debug(
                        "  Parsed '\(entry.combo, privacy: .public)': capslock keyCode=\(keyCode, privacy: .public)"
                    )
                case .spaceModifier(let keyCode):
                    space.append(binding)
                    Log.keybindings.debug(
                        "  Parsed '\(entry.combo, privacy: .public)': space keyCode=\(keyCode, privacy: .public)"
                    )
                case .mouseButton(let button, let modifiers):
                    mouse.append(binding)
                    let fl = modifiers.rawValue
                    Log.keybindings.debug(
                        "  Parsed '\(entry.combo, privacy: .public)': mouse btn=\(button, privacy: .public) flags=\(fl, privacy: .public)"
                    )
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
            Log.keybindings.info("No keybindings configured — skipping event tap")
            Log.stderr("  ⚠ keybindings: none configured")
            return
        }

        let std = standard.count
        let caps = capsLock.count
        let spc = space.count
        let mse = mouse.count
        let summary = "\(std)/\(caps)/\(spc)/\(mse) std/caps/spc/mouse"
        Log.keybindings.info(
            "Starting event tap: \(totalBindings, privacy: .public) bindings (\(summary, privacy: .public))"
        )

        // Try to create the event tap (needs Accessibility permission).
        // We skip preflight checks — CGEvent.tapCreate is the real test.
        guard eventTapHandler.start() else {
            let message =
                "Event tap failed — grant Accessibility permission"
            Log.keybindings.error(
                "Event tap creation failed — all \(totalBindings, privacy: .public) bindings inactive"
            )
            for entry in currentEntries where bindingErrors[entry.combo] == nil {
                bindingErrors[entry.combo] = message
            }
            return
        }
        eventTapRunning = true
        Log.keybindings.info(
            "Applied \(totalBindings, privacy: .public) keybinding(s) (\(summary, privacy: .public))"
        )
        Log.stderr("  ✓ keybindings: \(totalBindings) applied")

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
                    if CapsLockMonitor.shared.start() {
                        capsLockMonitorRunning = true
                    } else {
                        // IOKit HID open failed despite CGEvent check
                        let msg = "CapsLock monitor failed — remove and re-add app in Input Monitoring"
                        Log.keybindings.error("\(msg, privacy: .public)")
                        Log.stderr("  ✗ CapsLock: IOKit HID denied — re-grant Input Monitoring")
                        setCapsLockErrors(msg)
                    }
                }
            } else {
                let msg =
                    "CapsLock combos need Input Monitoring permission"
                Log.keybindings.warning("\(msg, privacy: .public)")
                setCapsLockErrors(msg)
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

    private func setCapsLockErrors(_ message: String) {
        for entry in currentEntries {
            if let ct = try? KeyComboParser.parse(entry.combo),
               case .capsLockModifier = ct {
                bindingErrors[entry.combo] = message
            }
        }
    }

    // MARK: - Action Execution

    private static func executeAction(
        _ actionID: ActionID,
        moduleRegistry: ModuleRegistry,
        eventBus: EventBus
    ) async {
        var currentID = actionID
        var currentValues: [String: Any] = [:]
        let maxChainDepth = 5

        for depth in 0..<maxChainDepth {
            guard let action = await moduleRegistry.findAction(id: currentID) else {
                Log.keybindings.error("Action not found: \(currentID, privacy: .public)")
                await eventBus.publish(.actionFailed(currentID, message: "Action not found"))
                return
            }

            let moduleID = String(currentID.rawValue.prefix(while: { $0 != "." }))
            let result: ActionResult
            do {
                result = try await action.run(with: currentValues)
                await eventBus.publish(.actionExecuted(currentID, moduleID: moduleID))
            } catch {
                Log.keybindings.error("Action \(currentID, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                await eventBus.publish(.actionFailed(currentID, message: error.localizedDescription))
                return
            }

            guard case let .chain(nextID, stringValues) = result else {
                return
            }

            Log.keybindings.info("Chaining \(currentID, privacy: .public) → \(nextID, privacy: .public) (depth \(depth, privacy: .public))")
            currentID = nextID
            currentValues = [:]
            for (key, value) in stringValues {
                currentValues[key] = value
            }
        }

        Log.keybindings.error("Chain depth exceeded at \(currentID, privacy: .public)")
        await eventBus.publish(.actionFailed(currentID, message: "Chain depth exceeded"))
    }
}
