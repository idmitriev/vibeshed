@testable import ShowreelCore
import Testing
import Yams

struct ConfigMergeTests {
    @Test func mergesMappingsKeyByKeyAndReplacesLists() throws {
        let base = """
        keybindings:
          - { combo: "capslock+space", action: "app/togglePicker" }
        modules:
          window:
          math: { decimalPlaces: 6 }
        """
        let overlay = """
        modules:
          math: { enableCurrency: false }
          github: { maxResults: 5 }
        """
        let merged = try ConfigMerge.merge([base, overlay], secrets: [:])
        let node = try #require(try Yams.compose(yaml: merged))
        #expect(node["modules"]?["math"]?["decimalPlaces"]?.int == 6)
        #expect(node["modules"]?["math"]?["enableCurrency"]?.bool == false)
        #expect(node["modules"]?["github"]?["maxResults"]?.int == 5)
        #expect(node["keybindings"]?.sequence?.count == 1)
    }

    @Test func fillsSecretsAndDefaults() throws {
        let text = "id: ${CLIENT_ID}\ntoken: ${TOKEN:-null}\n"
        #expect(try ConfigMerge.substitute(text, secrets: ["CLIENT_ID": "abc"]) == "id: abc\ntoken: null\n")
        #expect(throws: SceneError.self) { try ConfigMerge.substitute(text, secrets: [:]) }
    }

    @Test func parsesEnvFiles() {
        let env = ConfigMerge.parseEnv("# comment\nA=1\n\nB=two=2\n")
        #expect(env == ["A": "1", "B": "two=2"])
    }
}
