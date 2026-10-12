@testable import Vibeshed
import XCTest

@MainActor
final class HomebrewArrivalTests: XCTestCase {
    private func environment(with brew: String?) -> SoftwareEnvironment {
        SoftwareEnvironment(isAppInstalled: { _ in false }, fileExists: { $0 == brew }, homeDirectory: "/Users/test")
    }

    func testWaitsWhileTheInstallAliasIsThereWithoutTheModule() throws {
        let bareMac = DefaultConfig.yaml(detected: [])
        XCTAssertTrue(HomebrewArrival.isWaiting(for: try ConfigManager.parseYAML(bareMac)))

        let homebrew = try XCTUnwrap(HomebrewArrival.homebrew(in: environment(with: "/opt/homebrew/bin/brew")))
        let edit = ConfigEditor.enablingModules([DefaultConfig.Entry(homebrew)], in: bareMac)
        XCTAssertEqual(edit.enabled, ["homebrew"])
        let enabled = try ConfigManager.parseYAML(edit.yaml)
        XCTAssertNotNil(enabled.moduleConfigs["homebrew"])
        XCTAssertFalse(HomebrewArrival.isWaiting(for: enabled), "stops once the module is on")

        // A config written on a Mac that had Homebrew has no alias to wait on.
        let detected = SoftwareIntegration.detect(in: environment(with: "/usr/local/bin/brew"))
        let withBrew = try ConfigManager.parseYAML(DefaultConfig.yaml(detected: detected))
        XCTAssertFalse(HomebrewArrival.isWaiting(for: withBrew))
    }

    func testFindsBrewAtEitherPrefix() throws {
        XCTAssertNil(HomebrewArrival.homebrew(in: environment(with: nil)))
        let appleSilicon = try XCTUnwrap(HomebrewArrival.homebrew(in: environment(with: "/opt/homebrew/bin/brew")))
        XCTAssertEqual(appleSilicon.moduleID, "homebrew")
        XCTAssertEqual(appleSilicon.settings, [])
        let intel = try XCTUnwrap(HomebrewArrival.homebrew(in: environment(with: "/usr/local/bin/brew")))
        XCTAssertEqual(intel.settings, [#"brewPath: "/usr/local/bin/brew""#])
    }
}
