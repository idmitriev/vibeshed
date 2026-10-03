@testable import Vibeshed
import XCTest

final class SoftwareIntegrationTests: XCTestCase {
    func testFindsNothingOnABareMac() {
        XCTAssertEqual(SoftwareIntegration.detect(in: mac()), [])
    }

    func testEnablesModulesForInstalledAppsAndCLIs() {
        let detected = SoftwareIntegration.detect(in: mac(
            apps: ["com.apple.Safari", "com.spotify.client", "com.openai.codex", "com.todesktop.230313mzl4w4u92"],
            paths: ["/opt/homebrew/bin/brew", "/Users/test/.claude"]
        ))
        XCTAssertEqual(detected.map(\.moduleID), ["browser", "homebrew", "anthropic", "openai", "vscode", "spotify"])
        XCTAssertEqual(software("browser", in: detected), ["Safari"])
        XCTAssertEqual(software("anthropic", in: detected), ["Claude Code"])
        XCTAssertEqual(software("openai", in: detected), ["ChatGPT"])
        XCTAssertEqual(software("vscode", in: detected), ["Cursor"])
    }

    func testExpandsTheHomeDirectory() {
        let detected = SoftwareIntegration.detect(in: mac(paths: ["/Users/test/.codex"]))
        XCTAssertEqual(detected.map(\.moduleID), ["openai"])
        XCTAssertEqual(software("openai", in: detected), ["Codex"])
    }

    func testNamesEachFindOnce() {
        let detected = SoftwareIntegration.detect(in: mac(
            apps: ["com.anthropic.claudefordesktop"],
            paths: ["/Users/test/.claude", "/opt/homebrew/bin/claude"]
        ))
        XCTAssertEqual(software("anthropic", in: detected), ["Claude", "Claude Code"])
    }

    /// What an install added: integrations found now that weren't before, counting a
    /// cask's apps LaunchServices hasn't registered yet.
    func testFindsWhatAnInstallAdded() {
        let environment = mac(apps: ["com.apple.Safari"], paths: ["/opt/homebrew/bin/gh"])
        let before = SoftwareIntegration.detectedModuleIDs(in: environment)
        XCTAssertEqual(before, ["browser", "github"])

        let added = SoftwareIntegration.added(since: before, in: environment.adding(apps: ["com.spotify.client"]))
        XCTAssertEqual(added.map(\.moduleID), ["spotify"])
        XCTAssertEqual(SoftwareIntegration.added(since: before, in: environment), [])
    }

    func testHomebrewOnIntelGetsItsPath() {
        let detected = SoftwareIntegration.detect(in: mac(paths: ["/usr/local/bin/brew"]))
        XCTAssertEqual(detected.first?.settings, [#"brewPath: "/usr/local/bin/brew""#])
    }

    func testHomebrewOnAppleSiliconKeepsTheDefault() {
        let detected = SoftwareIntegration.detect(in: mac(paths: ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]))
        XCTAssertEqual(detected.first?.settings, [])
        XCTAssertEqual(HomebrewConfig().brewPath, "/opt/homebrew/bin/brew")
    }

    /// The config sections name modules that exist, and work with an empty section.
    func testNamesRealModulesWithUsableDefaults() async {
        let modules: [any Module] = [
            BrowserModule(), HomebrewModule(), AISessionsModule<AnthropicProvider>(),
            AISessionsModule<OpenAIProvider>(), RecentProjectsModule<VSCodeProvider>(),
            RecentProjectsModule<JetBrainsProvider>(), RecentProjectsModule<ZedProvider>(), ITermModule(),
            GhosttyModule(), SpotifyModule(), TelegramModule(), ZoomModule(), GitHubModule(),
        ]
        var ids: Set<String> = []
        for module in modules {
            await ids.insert(module.id)
        }
        XCTAssertEqual(ids, Set(SoftwareIntegration.all.map(\.moduleID)))

        for module in modules {
            let id = await module.id
            XCTAssertTrue(hasValidDefaults(module), "\(id) has no usable defaultConfig")
        }
    }

    // MARK: - Helpers

    private func mac(apps: Set<String> = [], paths: Set<String> = []) -> SoftwareEnvironment {
        SoftwareEnvironment(
            isAppInstalled: { apps.contains($0) },
            fileExists: { paths.contains($0) },
            homeDirectory: "/Users/test"
        )
    }

    private func software(_ moduleID: String, in detected: [DetectedIntegration]) -> [String]? {
        detected.first { $0.moduleID == moduleID }?.software
    }

    private func hasValidDefaults(_ module: any Module) -> Bool {
        func check<M: ModuleConfigurable>(_: M) -> Bool {
            M.defaultConfig.map { M.validate($0).isValid } ?? false
        }
        guard let configurable = module as? any ModuleConfigurable else { return false }
        return check(configurable)
    }
}
