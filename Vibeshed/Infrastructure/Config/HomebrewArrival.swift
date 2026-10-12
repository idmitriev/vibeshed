import Foundation

/// Turns the Homebrew module on once Homebrew is installed. On a Mac without it, the
/// first-launch config has an "Install Homebrew" alias that runs brew.sh's script in
/// Terminal, where Vibeshed can't see it finish; so while that alias is in the config
/// and the config has no `homebrew` section, this checks for `brew` every few seconds.
@MainActor
final class HomebrewArrival {
    static let checkInterval: TimeInterval = 3

    private let configManager: ConfigManager
    private let environment: SoftwareEnvironment
    private var timer: Timer?

    init(configManager: ConfigManager, environment: SoftwareEnvironment = .live) {
        self.configManager = configManager
        self.environment = environment
    }

    /// Starts checking, unless Homebrew is already here (a commented-out module stays off)
    /// or the config isn't waiting for it.
    func start() {
        guard timer == nil, Self.isWaiting(for: configManager.config),
              Self.homebrew(in: environment) == nil
        else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func check() {
        guard Self.isWaiting(for: configManager.config) else { return stop() }
        guard let homebrew = Self.homebrew(in: environment) else { return }
        stop()
        let enabled = configManager.enableModules([DefaultConfig.Entry(homebrew)])
        Log.config.info("Homebrew is installed; enabled: \(enabled.joined(separator: ", "), privacy: .public)")
    }

    /// Whether `config` has the "Install Homebrew" alias and no Homebrew module.
    static func isWaiting(for config: AppConfig) -> Bool {
        config.moduleConfigs["homebrew"] == nil
            && config.aliases.contains { $0.parameters?["command"] == DefaultConfig.homebrewInstallCommand }
    }

    /// The Homebrew module's section, when `brew` is installed.
    static func homebrew(in environment: SoftwareEnvironment) -> DetectedIntegration? {
        let homebrew = SoftwareIntegration.all.filter { $0.moduleID == "homebrew" }
        return SoftwareIntegration.detect(in: environment, among: homebrew).first
    }
}
