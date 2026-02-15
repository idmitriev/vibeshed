import Foundation

@MainActor
@Observable
final class ModuleRegistry {
    private(set) var moduleIDs: [String] = []
    private(set) var configErrors: [String: String] = [:]
    private(set) var permissionErrors: [String: PermissionError] = [:]
    private var modules: [String: any Module] = [:]
    private var configDecoders: [String: ModuleConfigDecoder] = [:]
    private var pendingModules: [String: any Module] = [:]
    private let eventBus: EventBus
    private let configManager: ConfigManager
    private let permissionsManager: PermissionsManager

    init(eventBus: EventBus, configManager: ConfigManager, permissionsManager: PermissionsManager) {
        self.eventBus = eventBus
        self.configManager = configManager
        self.permissionsManager = permissionsManager
    }

    func startListeningForConfigChanges() {
        Task { [weak self] in
            guard let self else { return }
            let (_, stream) = await eventBus.subscribe()
            for await event in stream {
                switch event {
                case .configReloaded:
                    await self.propagateConfigChanges()
                case .permissionChanged:
                    await self.retryPendingModules()
                default:
                    break
                }
            }
        }
    }

    func register(_ module: any Module) async throws {
        let id = await module.id

        // 1. Check permissions before config and init
        let required = type(of: module).requiredPermissions
        if !required.isEmpty {
            let missing = permissionsManager.missingPermissions(from: required)
            if !missing.isEmpty {
                let error = PermissionError.denied(moduleID: id, permissions: missing)
                permissionErrors[id] = error
                pendingModules[id] = module
                Log.modules.error("Module '\(id)' not loaded: \(error.localizedDescription)")
                await eventBus.publish(.modulePermissionError(moduleID: id, missing: missing))
                return
            }
        }

        // 2. Validate config
        let decoder = buildConfigDecoder(for: module, id: id)

        if let decoder {
            let rawYAML = configManager.config.moduleConfigs[id]
            do {
                try decoder.validate(rawYAML)
            } catch {
                let message = (error as? ModuleConfigError)?.errorDescription
                    ?? error.localizedDescription
                configErrors[id] = message
                Log.modules.error("Module '\(id)' not loaded: \(message)")
                await eventBus.publish(.moduleConfigError(moduleID: id, message: message))
                return
            }
        }

        // 3. Initialize
        let context = ModuleContext(
            eventBus: eventBus,
            loggerFactory: { subcategory in
                Log.module("\(id).\(subcategory)")
            }
        )
        try await module.initialize(context: context)

        // 4. Apply config
        if let decoder {
            let rawYAML = configManager.config.moduleConfigs[id]
            try await decoder.apply(rawYAML)
        }

        modules[id] = module
        if let decoder { configDecoders[id] = decoder }
        moduleIDs.append(id)
        permissionErrors.removeValue(forKey: id)
        pendingModules.removeValue(forKey: id)
        Log.modules.info("Registered module: \(id)")
        await eventBus.publish(.moduleRegistered(id))
    }

    func unregister(id: String) async {
        guard let module = modules.removeValue(forKey: id) else { return }
        moduleIDs.removeAll { $0 == id }
        configDecoders.removeValue(forKey: id)
        configErrors.removeValue(forKey: id)
        permissionErrors.removeValue(forKey: id)
        pendingModules.removeValue(forKey: id)
        await module.teardown()
        Log.modules.info("Unregistered module: \(id)")
        await eventBus.publish(.moduleUnregistered(id))
    }

    func queryAll(
        query: String,
        scoring: ScoringContext
    ) async -> [any Action] {
        let allModules = Array(modules.values)

        let allActions = await withTaskGroup(of: [any Action].self) { group in
            for module in allModules {
                group.addTask {
                    guard await module.isEnabled else { return [] }
                    return await module.provideActions(query: query, scoring: scoring)
                }
            }
            var results: [any Action] = []
            for await batch in group {
                results.append(contentsOf: batch)
            }
            return results
        }

        return allActions.sorted { a, b in
            let scoreA = a.relevanceScore * 0.7 + scoring.usageBoost(for: a.id) * 0.3
            let scoreB = b.relevanceScore * 0.7 + scoring.usageBoost(for: b.id) * 0.3
            return scoreA > scoreB
        }
    }

    var requiredPermissions: Set<Permission> {
        var result = Set<Permission>()
        for module in modules.values {
            result.formUnion(type(of: module).requiredPermissions)
        }
        for module in pendingModules.values {
            result.formUnion(type(of: module).requiredPermissions)
        }
        return result
    }

    func module(id: String) -> (any Module)? {
        modules[id]
    }

    func findAction(id: ActionID) async -> (any Action)? {
        let moduleID = String(id.rawValue.prefix(while: { $0 != "." }))
        guard let module = modules[moduleID] else { return nil }
        let actions = await module.provideActions(
            query: "",
            scoring: ScoringContext(usageCounts: [:], lastUsedDates: [:], query: "", systemContext: nil)
        )
        return actions.first { $0.id == id }
    }

    // MARK: - Private

    private func buildConfigDecoder(
        for module: any Module,
        id: String
    ) -> ModuleConfigDecoder? {
        func open<M: ModuleConfigurable>(_ m: M, id: String) -> ModuleConfigDecoder {
            ModuleConfigDecoder.make(for: m, moduleID: id)
        }
        guard let configurable = module as? any ModuleConfigurable else {
            return nil
        }
        return open(configurable, id: id)
    }

    private func propagateConfigChanges() async {
        for (id, decoder) in configDecoders {
            let rawYAML = configManager.config.moduleConfigs[id]
            do {
                try await decoder.apply(rawYAML)
                configErrors.removeValue(forKey: id)
            } catch {
                let message = (error as? ModuleConfigError)?.errorDescription
                    ?? error.localizedDescription
                configErrors[id] = message
                Log.modules.error("Config change rejected for module '\(id)': \(message)")
                await eventBus.publish(.moduleConfigError(moduleID: id, message: message))
            }
        }
    }

    private func retryPendingModules() async {
        let pending = pendingModules
        for (id, module) in pending {
            let required = type(of: module).requiredPermissions
            let missing = permissionsManager.missingPermissions(from: required)
            if missing.isEmpty {
                Log.modules.info("Retrying module '\(id)' after permission grant")
                Log.stderr("  ↻ module: \(id) — retrying after permission grant")
                do {
                    try await register(module)
                    Log.stderr("  ✓ module: \(id) — loaded")
                } catch {
                    Log.stderr("  ✗ module: \(id) — retry failed: \(error.localizedDescription)")
                    Log.modules.error("Retry failed for module '\(id)': \(error.localizedDescription)")
                }
            }
        }
    }
}
