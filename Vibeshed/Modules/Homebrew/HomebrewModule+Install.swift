import Foundation

/// The install actions' work. Installing something a Vibeshed module works with
/// (Spotify, iTerm, `gh`, …) also turns that module on in config.yaml.
extension HomebrewModule {
    func install(formula name: String, brewPath: String) async throws -> ActionResult {
        let before = SoftwareIntegration.detectedModuleIDs()
        let output = try await HomebrewManager.installFormula(name, brewPath: brewPath)
        invalidatePackageCache()
        let enabled = await enableModulesForInstall(since: before)
        let lines = [enabled, HomebrewManager.installSummary(output)].compactMap(\.self)
        return .showResult(title: "Installed \(name)", body: lines.joined(separator: "\n"))
    }

    func install(cask name: String, brewPath: String) async throws -> ActionResult {
        let before = SoftwareIntegration.detectedModuleIDs()
        let summary = try await HomebrewManager.installSummary(
            HomebrewManager.installCask(name, brewPath: brewPath)
        )
        invalidatePackageCache()
        // The install already succeeded; a failed app lookup or launch shouldn't turn it into an error.
        let appPaths = await (try? HomebrewManager.caskAppPaths(name, brewPath: brewPath)) ?? []
        let enabled = await enableModulesForInstall(since: before, appPaths: appPaths)
        let launched = await HomebrewManager.launchFirstApp(at: appPaths).map { path in
            "Launched " + URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        }
        let lines = [launched, enabled, summary].compactMap(\.self)
        return .showResult(title: "Installed \(name)", body: lines.joined(separator: "\n"))
    }

    /// Turns on the modules for software that wasn't there `before` (module IDs) and is
    /// now. A cask's `appPaths` count even if LaunchServices hasn't picked them up yet.
    /// Returns a line for the result, or nil when no module was turned on.
    private func enableModulesForInstall(since before: Set<String>, appPaths: [String] = []) async -> String? {
        let bundleIDs = Set(appPaths.compactMap { Bundle(path: $0)?.bundleIdentifier })
        let added = SoftwareIntegration.added(since: before, in: SoftwareEnvironment.live.adding(apps: bundleIDs))
        guard !added.isEmpty else { return nil }
        let enabled = await enableModules(added)
        guard !enabled.isEmpty else { return nil }
        log.info("Turned on modules after an install: \(enabled.joined(separator: ", "), privacy: .public)")
        let modules = ListFormatter.localizedString(byJoining: enabled)
        return "Turned on the \(modules) \(enabled.count == 1 ? "module" : "modules") in config.yaml"
    }
}
