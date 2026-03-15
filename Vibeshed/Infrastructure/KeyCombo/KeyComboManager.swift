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
    private let showParameterInput: (any Action) -> Void

    private let focusedAppTracker = FocusedAppTracker()
    private let eventTapHandler: EventTapHandler
    private var currentEntries: [KeyBindingEntry] = []
    private var eventTapRunning = false
    private var capsLockMonitorRunning = false

    init(
        eventBus: EventBus,
        configManager: ConfigManager,
        moduleRegistry: ModuleRegistry,
        permissionsManager: PermissionsManager,
        togglePicker: @escaping () -> Void,
        showParameterInput: @escaping (any Action) -> Void
    ) {
        self.eventBus = eventBus
        self.configManager = configManager
        self.moduleRegistry = moduleRegistry
        self.permissionsManager = permissionsManager
        self.togglePicker = togglePicker
        self.showParameterInput = showParameterInput
        self.eventTapHandler = EventTapHandler(
            focusedAppTracker: focusedAppTracker
        ) { [weak moduleRegistry, weak eventBus, togglePicker, showParameterInput] actionID in
            Task { @MainActor in
                Log.keybindings.info("Executing action: \(actionID.rawValue, privacy: .public)")
                // Built-in actions
                if actionID.rawValue == "app/togglePicker" {
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
                    eventBus: eventBus,
                    showParameterInput: showParameterInput
                )
            }
        }
    }

    // MARK: - Public

    func startListening() {
        focusedAppTracker.start()

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
            let scope = entry.app ?? "global"
            let target = entry.action ?? entry.remap ?? "?"
            Log.keybindings.debug(
                "  entry: '\(entry.combo, privacy: .public)' → '\(target, privacy: .public)' [\(scope, privacy: .public)]"
            )
        }
        currentEntries = entries
        rebindAll()
    }

    func stop() {
        eventTapHandler.stop()
        eventTapRunning = false
        focusedAppTracker.stop()
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
        Log.keybindings.info("Config reloaded: \(newEntries.count, privacy: .public) entries (was \(oldCount, privacy: .public))")
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
            // Skip remap entries — only validate action bindings
            guard let action = entry.action else { continue }
            let actionID = ActionID(action)
            guard actionID.rawValue != "app/togglePicker" else { continue }

            let moduleID = actionID.moduleID
            // Only warn if the module is registered but the action doesn't exist
            guard moduleRegistry.module(id: moduleID) != nil else { continue }

            let errorKey = bindingErrorKey(combo: entry.combo, app: entry.app)
            Task { [weak self] in
                guard let self else { return }
                if await moduleRegistry.findAction(id: actionID) == nil {
                    bindingErrors[errorKey] = "Action '\(action)' not found in module '\(moduleID)'"
                    Log.keybindings.warning(
                        "Action '\(action, privacy: .public)' for combo '\(entry.combo, privacy: .public)' not available"
                    )
                } else {
                    bindingErrors.removeValue(forKey: errorKey)
                }
            }
        }
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
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

        // Categorize unified entries into bindings and remaps
        var standard: [ResolvedBinding] = []
        var capsLock: [ResolvedBinding] = []
        var space: [ResolvedBinding] = []
        var tab: [ResolvedBinding] = []
        var mouse: [ResolvedBinding] = []
        var resolvedRemaps: [ResolvedRemap] = []
        var resolvedTabRemaps: [ResolvedRemap] = []
        var resolvedMouseRemaps: [ResolvedMouseRemap] = []
        var seenCombos: Set<String> = []

        for entry in currentEntries {
            let errorKey = bindingErrorKey(combo: entry.combo, app: entry.app)

            // Validate: must have exactly one of action or remap
            if entry.action != nil, entry.remap != nil {
                bindingErrors[errorKey] = "Entry has both 'action' and 'remap' — use one or the other"
                continue
            }
            if entry.action == nil, entry.remap == nil {
                bindingErrors[errorKey] = "Entry has neither 'action' nor 'remap'"
                continue
            }

            // Duplicate check (same combo + app scope)
            let dupeKey = "\(entry.combo.lowercased())@\(entry.app ?? "*")"
            if seenCombos.contains(dupeKey) {
                bindingErrors[errorKey] = KeyComboError.duplicateBinding(entry.combo).localizedDescription
                Task { await eventBus.publish(.keybindingError(combo: entry.combo, message: bindingErrors[errorKey]!)) }
                continue
            }
            seenCombos.insert(dupeKey)

            do {
                let comboType = try KeyComboParser.parse(entry.combo)

                if let action = entry.action {
                    // Action binding
                    let binding = ResolvedBinding(
                        comboType: comboType,
                        actionID: ActionID(action),
                        rawCombo: entry.combo,
                        app: entry.app
                    )
                    switch comboType {
                    case .standard: standard.append(binding)
                    case .capsLockModifier: capsLock.append(binding)
                    case .spaceModifier: space.append(binding)
                    case .tabModifier: tab.append(binding)
                    case .mouseButton: mouse.append(binding)
                    }
                } else if let remap = entry.remap {
                    // Remap entry
                    switch comboType {
                    case .mouseButton(let button, let modifiers):
                        let (toKeyCode, toModifiers) = try KeyComboParser.parseStandard(remap)
                        resolvedMouseRemaps.append(ResolvedMouseRemap(
                            button: button, modifiers: modifiers,
                            toKeyCode: toKeyCode, toModifiers: toModifiers,
                            rawFrom: entry.combo, rawTo: remap
                        ))
                    case .standard, .tabModifier:
                        let (toKeyCode, toModifiers) = try KeyComboParser.parseStandard(remap)
                        let resolved = ResolvedRemap(
                            fromType: comboType, toKeyCode: toKeyCode, toModifiers: toModifiers,
                            app: entry.app, rawFrom: entry.combo, rawTo: remap
                        )
                        if case .tabModifier = comboType {
                            resolvedTabRemaps.append(resolved)
                        } else {
                            resolvedRemaps.append(resolved)
                        }
                    default:
                        let err = KeyComboError.invalidRemap(
                            from: entry.combo, to: remap,
                            reason: "remap source must be standard, tab, or mouse combo (not capslock/space)"
                        )
                        bindingErrors[errorKey] = err.localizedDescription
                    }
                }
            } catch {
                let message = error.localizedDescription
                bindingErrors[errorKey] = message
                Log.keybindings.error("Invalid entry '\(entry.combo, privacy: .public)': \(message, privacy: .public)")
                Task { await eventBus.publish(.keybindingError(combo: entry.combo, message: message)) }
            }
        }

        // Update bindings on the handler (thread-safe)
        eventTapHandler.updateBindings(
            standard: standard,
            capsLock: capsLock,
            space: space,
            tab: tab,
            mouse: mouse,
            remaps: resolvedRemaps,
            tabRemapList: resolvedTabRemaps,
            mouseRemapList: resolvedMouseRemaps
        )

        // Start event tap if we have any bindings or remaps
        let totalBindings = standard.count + capsLock.count + space.count + tab.count + mouse.count
        let totalRemaps = resolvedRemaps.count + resolvedTabRemaps.count + resolvedMouseRemaps.count
        guard totalBindings + totalRemaps > 0 else {
            Log.keybindings.info("No keybindings or remaps configured — skipping event tap")
            Log.stderr("  ⚠ keybindings: none configured")
            return
        }

        let std = standard.count
        let caps = capsLock.count
        let spc = space.count
        let tb = tab.count
        let mse = mouse.count
        let summary = "\(std)/\(caps)/\(spc)/\(tb)/\(mse) std/caps/spc/tab/mouse + \(totalRemaps) remaps"
        Log.keybindings.info(
            "Starting event tap: \(totalBindings + totalRemaps, privacy: .public) bindings+remaps (\(summary, privacy: .public))"
        )

        // Try to create the event tap (needs Accessibility permission).
        // We skip preflight checks — CGEvent.tapCreate is the real test.
        guard eventTapHandler.start() else {
            let message =
                "Event tap failed — grant Accessibility permission"
            Log.keybindings.error(
                "Event tap creation failed — all \(totalBindings + totalRemaps, privacy: .public) bindings+remaps inactive"
            )
            for entry in currentEntries where bindingErrors[bindingErrorKey(combo: entry.combo, app: entry.app)] == nil {
                bindingErrors[bindingErrorKey(combo: entry.combo, app: entry.app)] = message
            }
            return
        }
        eventTapRunning = true
        Log.keybindings.info(
            "Applied \(totalBindings + totalRemaps, privacy: .public) keybinding(s)+remap(s) (\(summary, privacy: .public))"
        )
        Log.stderr("  ✓ keybindings: \(totalBindings) applied + \(totalRemaps) remaps")

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
                bindingErrors[bindingErrorKey(combo: entry.combo, app: entry.app)] = message
            }
        }
    }

    private func bindingErrorKey(combo: String, app: String?) -> String {
        if let app {
            return "\(combo)@\(app)"
        }
        return combo
    }

    // MARK: - Action Execution

    private static func executeAction(
        _ actionID: ActionID,
        moduleRegistry: ModuleRegistry,
        eventBus: EventBus,
        showParameterInput: @escaping (any Action) -> Void
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

            // If the action has required parameters and none were provided,
            // show the picker in parameter-input mode instead of executing.
            let requiredParams = action.parameters.filter(\.isRequired)
            if !requiredParams.isEmpty, currentValues.isEmpty {
                Log.keybindings.info(
                    "Action \(currentID, privacy: .public) needs parameters — showing picker"
                )
                showParameterInput(action)
                return
            }

            let moduleID = currentID.moduleID
            let result: ActionResult
            do {
                result = try await action.run(with: currentValues)
                await eventBus.publish(.actionExecuted(currentID, moduleID: moduleID))
            } catch {
                let msg = error.localizedDescription
                Log.keybindings.error(
                    "Action \(currentID, privacy: .public) failed: \(msg, privacy: .public)"
                )
                await eventBus.publish(.actionFailed(currentID, message: msg))
                return
            }

            guard case let .chain(nextID, stringValues) = result else {
                return
            }

            Log.keybindings.info(
                "Chaining \(currentID, privacy: .public) → \(nextID, privacy: .public) (depth \(depth, privacy: .public))"
            )
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
