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
    private var currentRemaps: [AppRemapGroup] = []
    private var currentMouseRemaps: [MouseRemapEntry] = []
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
            Log.keybindings.debug(
                "  entry: '\(entry.combo, privacy: .public)' → '\(entry.action, privacy: .public)' [\(scope, privacy: .public)]"
            )
        }
        currentEntries = entries
        currentRemaps = configManager.config.appRemaps
        currentMouseRemaps = configManager.config.mouseRemaps
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
        currentRemaps = []
        currentMouseRemaps = []
        bindingErrors = [:]
    }

    // MARK: - Private

    private func handleConfigReloaded() {
        let newEntries = configManager.config.keybindings
        let newRemaps = configManager.config.appRemaps
        let newMouseRemaps = configManager.config.mouseRemaps
        guard newEntries != currentEntries || newRemaps != currentRemaps || newMouseRemaps != currentMouseRemaps else {
            Log.keybindings.debug("Config reloaded but keybindings/remaps unchanged")
            return
        }
        let oldCount = currentEntries.count
        let oldRemapCount = currentRemaps.count
        let mrmp = newMouseRemaps.count
        let summary = "\(newEntries.count) bindings (was \(oldCount)), \(newRemaps.count) remaps (was \(oldRemapCount)), \(mrmp) mouseRemaps"
        Log.keybindings.info("Config reloaded: \(summary, privacy: .public)")
        currentEntries = newEntries
        currentRemaps = newRemaps
        currentMouseRemaps = newMouseRemaps
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

            let errorKey = bindingErrorKey(combo: entry.combo, app: entry.app)
            Task { [weak self] in
                guard let self else { return }
                if await moduleRegistry.findAction(id: actionID) == nil {
                    bindingErrors[errorKey] = "Action '\(entry.action)' not found in module '\(moduleID)'"
                    Log.keybindings.warning(
                        "Action '\(entry.action, privacy: .public)' for combo '\(entry.combo, privacy: .public)' not available"
                    )
                } else {
                    bindingErrors.removeValue(forKey: errorKey)
                }
            }
        }
    }

    // swiftlint:disable:next function_body_length
    private func rebindAll() {
        let entryCount = currentEntries.count
        let remapGroupCount = currentRemaps.count
        Log.keybindings.info("rebindAll: processing \(entryCount, privacy: .public) entries + \(remapGroupCount, privacy: .public) remap groups")

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

        // Parse keybinding entries
        var standard: [ResolvedBinding] = []
        var capsLock: [ResolvedBinding] = []
        var space: [ResolvedBinding] = []
        var mouse: [ResolvedBinding] = []
        var seenCombos: Set<String> = []

        for entry in currentEntries {
            // Duplicate key includes app scope so same combo can exist for different apps
            let dupeKey = "\(entry.combo.lowercased())@\(entry.app ?? "*")"
            let errorKey = bindingErrorKey(combo: entry.combo, app: entry.app)

            if seenCombos.contains(dupeKey) {
                bindingErrors[errorKey] = KeyComboError.duplicateBinding(entry.combo).localizedDescription
                Task { await eventBus.publish(.keybindingError(combo: entry.combo, message: bindingErrors[errorKey]!)) }
                continue
            }
            seenCombos.insert(dupeKey)

            do {
                let comboType = try KeyComboParser.parse(entry.combo)
                let binding = ResolvedBinding(
                    comboType: comboType,
                    actionID: ActionID(entry.action),
                    rawCombo: entry.combo,
                    app: entry.app
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
                bindingErrors[errorKey] = message
                Log.keybindings.error("Invalid keybinding '\(entry.combo, privacy: .public)': \(message, privacy: .public)")
                Task { await eventBus.publish(.keybindingError(combo: entry.combo, message: message)) }
            }
        }

        // Parse remap entries
        var resolvedRemaps: [ResolvedRemap] = []
        for group in currentRemaps {
            for remap in group.remaps {
                let errorKey = "remap:\(remap.from.lowercased())@\(group.app)"
                do {
                    let fromType = try KeyComboParser.parse(remap.from)
                    guard case .standard = fromType else {
                        let err = KeyComboError.invalidRemap(
                            from: remap.from, to: remap.to,
                            reason: "source must be a standard key combo (not capslock/space/mouse)"
                        )
                        bindingErrors[errorKey] = err.localizedDescription
                        continue
                    }
                    let (toKeyCode, toModifiers) = try KeyComboParser.parseStandard(remap.to)

                    resolvedRemaps.append(ResolvedRemap(
                        fromType: fromType,
                        toKeyCode: toKeyCode,
                        toModifiers: toModifiers,
                        app: group.app,
                        rawFrom: remap.from,
                        rawTo: remap.to
                    ))
                } catch {
                    bindingErrors[errorKey] = error.localizedDescription
                    let msg = error.localizedDescription
                    Log.keybindings.error(
                        "Invalid remap '\(remap.from, privacy: .public)' → '\(remap.to, privacy: .public)': \(msg, privacy: .public)"
                    )
                }
            }
        }

        // Parse mouse remap entries
        var resolvedMouseRemaps: [ResolvedMouseRemap] = []
        for entry in currentMouseRemaps {
            let errorKey = "mouseRemap:\(entry.from.lowercased())"
            do {
                let fromType = try KeyComboParser.parse(entry.from)
                guard case .mouseButton(let button, let modifiers) = fromType else {
                    let err = KeyComboError.invalidRemap(
                        from: entry.from, to: entry.to,
                        reason: "source must be a mouse button (e.g. mouse3, ctrl+mouse4)"
                    )
                    bindingErrors[errorKey] = err.localizedDescription
                    continue
                }
                let (toKeyCode, toModifiers) = try KeyComboParser.parseStandard(entry.to)
                resolvedMouseRemaps.append(ResolvedMouseRemap(
                    button: button,
                    modifiers: modifiers,
                    toKeyCode: toKeyCode,
                    toModifiers: toModifiers,
                    rawFrom: entry.from,
                    rawTo: entry.to
                ))
            } catch {
                bindingErrors[errorKey] = error.localizedDescription
                let msg = error.localizedDescription
                Log.keybindings.error(
                    "Invalid mouseRemap '\(entry.from, privacy: .public)' → '\(entry.to, privacy: .public)': \(msg, privacy: .public)"
                )
            }
        }

        // Update bindings on the handler (thread-safe)
        eventTapHandler.updateBindings(
            standard: standard,
            capsLock: capsLock,
            space: space,
            mouse: mouse,
            remaps: resolvedRemaps,
            mouseRemapList: resolvedMouseRemaps
        )

        // Start event tap if we have any bindings or remaps
        let totalBindings = standard.count + capsLock.count + space.count + mouse.count
        let totalRemaps = resolvedRemaps.count + resolvedMouseRemaps.count
        guard totalBindings + totalRemaps > 0 else {
            Log.keybindings.info("No keybindings or remaps configured — skipping event tap")
            Log.stderr("  ⚠ keybindings: none configured")
            return
        }

        let std = standard.count
        let caps = capsLock.count
        let spc = space.count
        let mse = mouse.count
        let summary = "\(std)/\(caps)/\(spc)/\(mse) std/caps/spc/mouse + \(totalRemaps) remaps"
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
        let hasBindings = currentEntries.contains { entry in
            (try? KeyComboParser.parse(entry.combo)) != nil
        }
        let hasRemaps = !currentRemaps.isEmpty
        let hasMouseRemaps = !currentMouseRemaps.isEmpty
        return hasBindings || hasRemaps || hasMouseRemaps
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

            let moduleID = String(currentID.rawValue.prefix(while: { $0 != "." }))
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
