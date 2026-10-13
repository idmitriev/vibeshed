import Foundation

/// Turns OpenAI model ids into the names OpenAI publishes them under.
enum OpenAIModelName {
    /// `gpt-5.3-codex` → "GPT-5.3-Codex", `gpt-5.4` → "GPT-5.4". Ids outside the
    /// `gpt-<version>` family (`o3`, internal review models) come back as-is.
    static func displayName(for id: String) -> String {
        let tokens = id.split(separator: "-")
        guard tokens.count >= 2, tokens[0] == "gpt",
              tokens[1].first?.isNumber == true
        else { return id }
        let words = tokens.dropFirst(2).map(\.capitalized)
        return (["GPT", String(tokens[1])] + words).joined(separator: "-")
    }
}
