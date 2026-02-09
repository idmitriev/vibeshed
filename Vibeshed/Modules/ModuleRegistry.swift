import Foundation

@MainActor
@Observable
final class ModuleRegistry {
    private(set) var moduleIDs: [String] = []
    private var modules: [String: any Module] = [:]
    private let eventBus: EventBus

    init(eventBus: EventBus) {
        self.eventBus = eventBus
    }

    func register(_ module: any Module) async throws {
        let id = await module.id
        let config = AppConfig.ModuleConfig(name: id)
        let context = ModuleContext(
            eventBus: eventBus,
            config: config,
            loggerFactory: { subcategory in
                Log.module("\(id).\(subcategory)")
            }
        )
        try await module.initialize(context: context)
        modules[id] = module
        moduleIDs.append(id)
        Log.modules.info("Registered module: \(id)")
        await eventBus.publish(.moduleRegistered(id))
    }

    func unregister(id: String) async {
        guard let module = modules.removeValue(forKey: id) else { return }
        moduleIDs.removeAll { $0 == id }
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

    func module(id: String) -> (any Module)? {
        modules[id]
    }

    func findAction(id: ActionID) async -> (any Action)? {
        let moduleID = String(id.rawValue.prefix(while: { $0 != "." }))
        guard let module = modules[moduleID] else { return nil }
        let actions = await module.provideActions(
            query: "",
            scoring: ScoringContext(usageCounts: [:], lastUsedDates: [:], query: "")
        )
        return actions.first { $0.id == id }
    }
}
