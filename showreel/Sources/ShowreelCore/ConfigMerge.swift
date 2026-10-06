import Foundation
import Yams

/// Builds the Vibeshed config a scene asks for: its YAML files merged in
/// order (mappings merge key by key, anything else is replaced), with
/// `${NAME}` / `${NAME:-default}` filled from `secrets`.
public enum ConfigMerge {
    public static func merge(_ texts: [String], secrets: [String: String]) throws -> String {
        var merged: Node?
        for text in texts {
            guard let node = try Yams.compose(yaml: substitute(text, secrets: secrets)) else { continue }
            merged = merged.map { merge($0, node) } ?? node
        }
        guard let merged else { return "" }
        return try Yams.serialize(node: merged)
    }

    static func merge(_ base: Node, _ overlay: Node) -> Node {
        guard case let .mapping(baseMapping) = base, case let .mapping(overlayMapping) = overlay else {
            return overlay
        }
        var result = baseMapping
        for (key, value) in overlayMapping {
            result[key] = result[key].map { merge($0, value) } ?? value
        }
        return .mapping(result)
    }

    public static func substitute(_ text: String, secrets: [String: String]) throws -> String {
        let pattern = try NSRegularExpression(pattern: #"\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-([^}]*))?\}"#)
        var output = ""
        var cursor = text.startIndex
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text), let nameRange = Range(match.range(at: 1), in: text)
            else { continue }
            let name = String(text[nameRange])
            let fallback = Range(match.range(at: 2), in: text).map { String(text[$0]) }
            guard let value = secrets[name] ?? fallback else {
                throw SceneError.invalid("the config needs ${\(name)}: add \(name)=… to showreel/.vm/secrets.env")
            }
            output += text[cursor ..< range.lowerBound] + value
            cursor = range.upperBound
        }
        return output + text[cursor...]
    }

    /// `NAME=value` lines; `#` comments and blank lines are skipped.
    public static func parseEnv(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else { continue }
            values[String(trimmed[..<equals])] = String(trimmed[trimmed.index(after: equals)...])
        }
        return values
    }
}
