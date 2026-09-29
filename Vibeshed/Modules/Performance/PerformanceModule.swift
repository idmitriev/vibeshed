import Foundation
import OSLog

/// CPU, memory, disk and network activity: current values and history in the
/// previews, and each action opens Activity Monitor on the matching tab.
actor PerformanceModule: ModuleConfigurable {
    let id = "performance"
    let displayName = "Performance"
    let iconName = "gauge.with.dots.needle.50percent"
    var isEnabled = true

    typealias Config = PerformanceConfig
    static var defaultConfig: Config? {
        .init()
    }

    private var config = PerformanceConfig()
    private var monitor: PerformanceMonitor?
    private var sampling: Task<Void, Never>?
    private let log = Log.module("performance")

    func initialize(context _: ModuleContext) async throws {
        let hardware = HardwareInfo.current()
        monitor = await MainActor.run { PerformanceMonitor(hardware: hardware) }
        log.info("Performance module initialized")
    }

    func teardown() async {
        sampling?.cancel()
        sampling = nil
    }

    func configDidUpdate(_ config: PerformanceConfig) async {
        let previous = self.config
        self.config = config
        let window = config.historyWindow
        let interval = config.sampleInterval
        await monitor?.configure(historyWindow: window, sampleInterval: interval)
        if sampling == nil
            || previous.sampleInterval != config.sampleInterval
            || previous.networkInterfaces != config.networkInterfaces
        {
            startSampling()
        }
        log.debug("Config updated")
    }

    static func validate(_ config: PerformanceConfig) -> ConfigValidationResult {
        var errors: [String] = []
        if !PerformanceConfig.sampleIntervalRange.contains(config.sampleInterval) {
            errors.append("sampleInterval must be between 0.5 and 60 seconds")
        }
        if !PerformanceConfig.historyMinutesRange.contains(config.historyMinutes) {
            errors.append("historyMinutes must be between 1 and 1440")
        }
        if let names = config.networkInterfaces,
           names.isEmpty || names.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
        {
            errors.append("networkInterfaces must list interface names such as en0, or be left out")
        }
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    func provideActions(query _: String, scoring _: ScoringContext) async -> [any Action] {
        guard let monitor else { return [] }
        let latest = await monitor.latest
        return PerformanceAction.Kind.all
            .filter { config.enabledActions?.contains($0.name) ?? true }
            .map { kind in
                let subtitle = PerformanceSummary.line(for: kind, sample: latest)
                return PerformanceAction(kind: kind, subtitle: subtitle, monitor: monitor)
            }
    }

    // MARK: - Sampling

    /// Samples in the background from launch on, so the history is there when the
    /// picker opens. Reading every counter takes well under a millisecond.
    private func startSampling() {
        sampling?.cancel()
        guard let monitor else { return }
        let interval = config.sampleInterval
        let selection = InterfaceSelection(names: config.networkInterfaces)
        sampling = Task.detached(priority: .utility) {
            var previous = PerformanceProbe.read(interfaces: selection)
            // The first sample comes sooner, so the views have data right after launch.
            var delay = min(1, interval)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(delay), tolerance: .seconds(interval / 10))
                guard !Task.isCancelled else { break }
                let current = PerformanceProbe.read(interfaces: selection)
                if let sample = PerformanceMath.sample(from: previous, to: current, date: Date()) {
                    await monitor.record(sample)
                }
                previous = current
                delay = interval
            }
        }
    }
}
