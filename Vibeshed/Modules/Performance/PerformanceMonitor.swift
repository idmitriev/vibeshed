import Foundation
import Observation

/// The latest sample and the history, as the views show them.
struct PerformanceSnapshot: Sendable, Equatable {
    var latest: PerformanceSample?
    var history = PerformanceHistory()
}

/// Samples, history and details fetched on demand, for the performance views. It
/// lives on the main actor so SwiftUI can observe it; the module's sampling task
/// feeds it.
@MainActor
@Observable
final class PerformanceMonitor {
    let hardware: HardwareInfo
    /// What the views draw. It follows every sample while the picker is on screen and
    /// holds still while it's hidden: Escape keeps the picker's views around, and they
    /// would otherwise redraw their charts every sample for nobody.
    private(set) var shown = PerformanceSnapshot()
    private(set) var historyWindow: TimeInterval
    private(set) var sampleInterval: TimeInterval
    /// Every process, fetched while a preview that lists processes is on screen.
    private(set) var processes: [ProcessUsage] = []
    private(set) var volumes: [VolumeUsage] = []
    private(set) var networkIdentity: NetworkIdentity?

    @ObservationIgnored private var current = PerformanceSnapshot()
    @ObservationIgnored private var isDisplayed = true
    @ObservationIgnored private var processesFetchedAt = Date.distantPast
    @ObservationIgnored private var volumesFetchedAt = Date.distantPast
    @ObservationIgnored private var identityFetchedAt = Date.distantPast

    init(hardware: HardwareInfo, historyWindow: TimeInterval = 3600, sampleInterval: TimeInterval = 2) {
        self.hardware = hardware
        self.historyWindow = historyWindow
        self.sampleInterval = sampleInterval
    }

    /// The newest sample, whether or not the views have caught up with it.
    var latest: PerformanceSample? {
        current.latest
    }

    func record(_ sample: PerformanceSample) {
        current.latest = sample
        current.history.append(PerformancePoint(sample), window: historyWindow)
        if isDisplayed {
            shown = current
        }
    }

    func configure(historyWindow: TimeInterval, sampleInterval: TimeInterval) {
        self.historyWindow = historyWindow
        self.sampleInterval = sampleInterval
        current.history.trim(window: historyWindow, now: Date())
        shown = current
    }

    /// Called by the views as the picker shows and hides.
    func setDisplayed(_ displayed: Bool) {
        guard displayed != isDisplayed else { return }
        isDisplayed = displayed
        if displayed {
            shown = current
        }
    }

    // MARK: - On-demand details

    // Previews run these while the picker is on screen (`whilePickerVisible`), which
    // cancels them when it hides or the preview goes away. Several previews may ask at
    // once; the fetch times keep that to one fetch.

    /// Refreshes `processes` every few seconds until cancelled.
    func trackProcesses() async {
        while !Task.isCancelled {
            if Date().timeIntervalSince(processesFetchedAt) >= 2 {
                processesFetchedAt = Date()
                processes = await TopProcesses.fetch()
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    func refreshVolumes() async {
        guard Date().timeIntervalSince(volumesFetchedAt) >= 10 else { return }
        volumesFetchedAt = Date()
        volumes = await Self.offMain { VolumeUsage.mounted() }
    }

    func refreshNetworkIdentity() async {
        guard Date().timeIntervalSince(identityFetchedAt) >= 10 else { return }
        identityFetchedAt = Date()
        networkIdentity = await Self.offMain { NetworkIdentity.current() }
    }

    private nonisolated static func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: work())
            }
        }
    }
}
