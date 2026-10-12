@testable import Vibeshed
import XCTest

final class TerminalManagerTests: XCTestCase {
    /// A running Terminal gets a new window from a bare `do script`.
    func testNewWindowScript() {
        let script = TerminalManager.newWindowScript(command: #"echo "hi" \ there"#, afterLaunch: false)
        XCTAssertEqual(script, #"""
        tell application id "com.apple.Terminal"
        do script "echo \"hi\" \\ there"
        activate
        end tell
        """#)

        let empty = TerminalManager.newWindowScript(command: nil, afterLaunch: false)
        XCTAssertTrue(empty.contains("\ndo script \"\"\n"))
    }

    /// Right after a launch, the command goes to the window Terminal opened, not a second one.
    func testNewWindowScriptAfterLaunchReusesTheStartupWindow() {
        let script = TerminalManager.newWindowScript(command: "brew doctor", afterLaunch: true)
        XCTAssertTrue(script.contains("repeat 30 times"))
        XCTAssertTrue(script.contains("\ndo script \"brew doctor\" in window 1\n"))
        XCTAssertTrue(script.contains("\nelse\ndo script \"brew doctor\"\nend if"), "opens one when none appears")
        XCTAssertTrue(script.hasSuffix("activate\nend tell"))
    }
}

final class TerminalModuleTests: XCTestCase {
    func testConfigDecodesPartialSections() throws {
        let json = Data(#"{ "commands": { "Top": "top" } }"#.utf8)
        let config = try JSONDecoder().decode(TerminalConfig.self, from: json)
        XCTAssertEqual(config.commands, ["Top": "top"])
        XCTAssertNil(config.enabledActions)
        XCTAssertEqual(try JSONDecoder().decode(TerminalConfig.self, from: Data("{}".utf8)), TerminalConfig())
        XCTAssertTrue(TerminalModule.validate(TerminalConfig()).isValid)
    }

    func testActionsAndCommands() {
        var config = TerminalConfig()
        config.commands = ["Top": "top", "Git": "git status"]
        let actions = TerminalModule.actions(config: config, appIcon: nil)
        XCTAssertEqual(
            actions.map(\.id.rawValue),
            [
                "terminal/newWindow",
                "terminal/runCommand",
                "terminal/cmd.\(StableID.hash("Git"))",
                "terminal/cmd.\(StableID.hash("Top"))",
            ]
        )
        XCTAssertEqual(actions[1].parameters.map(\.id), ["command"])
        XCTAssertEqual(actions[2].subtitle, "git status")
    }

    func testEnabledActionsAcceptTheCommandFamily() {
        var config = TerminalConfig()
        config.commands = ["Top": "top"]
        config.enabledActions = ["runCommand", "cmd"]
        let actions = TerminalModule.actions(config: config, appIcon: nil)
        XCTAssertEqual(
            TerminalModule.enabled(actions, config: config).map(\.id.actionName),
            ["runCommand", "cmd.\(StableID.hash("Top"))"]
        )
    }

    func testRunCommandWithoutACommandDoesNothing() async throws {
        let runCommand = try XCTUnwrap(TerminalModule.actions(config: TerminalConfig(), appIcon: nil).last)
        guard case .showResult = try await runCommand.run(with: ["command": "  "]) else {
            return XCTFail("a blank command shouldn't open Terminal")
        }
    }

    func testScriptsTerminal() async {
        let targets = await TerminalModule().automationTargets
        XCTAssertEqual(targets, ["com.apple.Terminal"])
    }
}
