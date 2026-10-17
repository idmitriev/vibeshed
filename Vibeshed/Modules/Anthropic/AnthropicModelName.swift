import Foundation

/// Turns Claude API model ids into the names people use for them.
enum AnthropicModelName {
    /// `claude-opus-5-5` → "Opus 5.5", `claude-3-5-sonnet-20241022` → "Sonnet 3.5".
    /// Also accepts Bedrock (`us.anthropic.claude-…-v1:0`) and Vertex (`…@20250929`)
    /// spellings. Ids that don't follow the family-plus-version shape come back as-is.
    static func displayName(for id: String) -> String {
        guard let start = id.range(of: "claude-") else { return id }
        // Vertex appends `@<date>`, Claude Code a `[1m]` context marker.
        let core = id[start.upperBound...]
            .prefix { $0 != "@" && $0 != "[" }
        let tokens = core.split(separator: "-").filter { token in
            let isDate = token.count == 8 && token.allSatisfy(\.isASCIIDigit)
            let isBedrockRevision = token.hasPrefix("v") && token.contains(":")
            return !isDate && !isBedrockRevision
        }
        let family = tokens.filter { $0.allSatisfy(\.isLetter) }
        let version = tokens.filter { $0.allSatisfy(\.isASCIIDigit) }
        guard family.count == 1, !version.isEmpty,
              family.count + version.count == tokens.count
        else { return id }
        return "\(family[0].capitalized) \(version.joined(separator: "."))"
    }
}

private extension Character {
    var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}
