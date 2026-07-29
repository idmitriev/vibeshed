import Foundation
import OSLog

actor ProcessesModule: ModuleConfigurable {
    let id = "processes"
    let displayName = "Processes"
    let iconName = "cpu"
    var isEnabled = true

    typealias Config = ProcessesConfig
    static var defaultConfig: Config? {
        .init()
    }

    private var config: ProcessesConfig = .init()
    private var context: ModuleContext?
    private let log = Log.module("processes")
    private var processCache: [ProcessEntry] = []
    private var cacheTimestamp: Date = .distantPast

    func initialize(context: ModuleContext) async throws {
        self.context = context
        log.info("Processes module initialized")
    }

    func configDidUpdate(_ config: ProcessesConfig) async {
        self.config = config
        invalidateCache()
        log.debug("Config updated, cache invalidated")
    }

    func provideActions(query: String, scoring: ScoringContext) async -> [any Action] {
        var actions: [any Action] = [buildKillByNameAction()]

        let processes = await getCachedOrFreshProcesses()
        for process in processes {
            actions.append(buildProcessAction(for: process))
        }
        return actions
    }

    func provideParameterOptions(
        for parameterID: String,
        in actionID: ActionID,
        query: String
    ) async -> [ParameterOption] {
        guard parameterID == "pid" else { return [] }

        let processes = await getCachedOrFreshProcesses()
        return processes.map { process in
            ParameterOption(
                id: String(process.pid),
                label: process.name,
                subtitle: subtitleText(for: process),
                iconName: "cpu",
                iconURL: process.bundleURL
            )
        }
    }

    // MARK: - Build Actions

    private func buildKillByNameAction() -> ProcessesAction {
        ProcessesAction(
            id: ActionID(module: "processes", name: "kill"),
            title: "Kill Process",
            subtitle: "Force-quit a process by name",
            iconName: "xmark.octagon",
            relevanceScore: 0.7,
            keywords: ["kill", "terminate", "force quit", "process", "end task"],
            parameters: [
                ActionParameter(
                    id: "pid",
                    label: "Process",
                    type: .dynamicSelection(hint: "pid"),
                    isRequired: true
                ),
            ],
            pid: 0
        ) { values in
            guard let pidString = values["pid"], let pid = Int32(pidString) else {
                return .showResult(title: "Error", body: "No process selected")
            }
            do {
                try ProcessesManager.kill(pid: pid)
            } catch {
                return .showResult(title: "Error", body: error.localizedDescription)
            }
            return .dismiss
        }
    }

    private func buildProcessAction(for process: ProcessEntry) -> ProcessesAction {
        let pid = process.pid
        let score = min(0.5 + process.cpuPercent / 200.0, 0.85)

        return ProcessesAction(
            id: ActionID(module: "processes", name: "process.\(pid)"),
            title: process.name,
            subtitle: subtitleText(for: process),
            iconName: "cpu",
            relevanceScore: score,
            keywords: ["process", "kill", "terminate", process.name.lowercased()],
            pid: pid,
            appBundleURL: process.bundleURL
        ) { _ in
            do {
                try ProcessesManager.kill(pid: pid)
            } catch {
                return .showResult(title: "Error", body: error.localizedDescription)
            }
            return .dismiss
        }
    }

    private func subtitleText(for process: ProcessEntry) -> String {
        var parts = [
            "PID \(process.pid)",
            String(format: "%.1f%% CPU", process.cpuPercent),
            String(format: "%.1f%% MEM", process.memPercent),
        ]
        if !process.ports.isEmpty {
            parts.append("Ports \(process.ports.map(String.init).joined(separator: ", "))")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Cache

    private func getCachedOrFreshProcesses() async -> [ProcessEntry] {
        let now = Date()
        if now.timeIntervalSince(cacheTimestamp) < config.cacheTTLSeconds, !processCache.isEmpty {
            return processCache
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let excluded = Set(config.excludedNames)
        let processes = ((try? await ProcessesManager.listProcesses(excludedNames: excluded)) ?? [])
            .filter { $0.pid != currentPID }
            .sorted { $0.cpuPercent > $1.cpuPercent }

        let limited = config.maxResults > 0 ? Array(processes.prefix(config.maxResults)) : processes
        processCache = limited
        cacheTimestamp = now
        return limited
    }

    private func invalidateCache() {
        processCache = []
        cacheTimestamp = .distantPast
    }
}
