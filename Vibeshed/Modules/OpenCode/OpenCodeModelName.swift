import Foundation

/// Turns OpenCode's stored model into a display name.
enum OpenCodeModelName {
    /// Sessions store the model as JSON, `{"id":"claude-opus-5-5","providerID":"anthropic",
    /// "variant":"max"}`. Older rows may hold a bare `provider/model` string instead, and
    /// router providers nest a vendor in the id (`anthropic/claude-…`); both drop the
    /// prefix. Claude and GPT ids get the vendor's own naming; others come back as-is.
    static func displayName(fromStored stored: String) -> String? {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var path = trimmed
        if trimmed.hasPrefix("{") {
            guard let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let modelID = json["id"] as? String
            else { return nil }
            path = modelID
        }
        guard let id = path.split(separator: "/").last.map(String.init) else { return nil }
        if id.contains("claude-") {
            return AnthropicModelName.displayName(for: id)
        }
        return OpenAIModelName.displayName(for: id)
    }
}
