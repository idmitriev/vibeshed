import Foundation

/// `codex://` deeplinks handled by the Codex desktop app, which ships as `ChatGPT.app`
/// and registers the `codex` scheme under the `com.openai.codex` bundle id.
enum OpenAIDeeplink {
    static let bundleID = "com.openai.codex"

    static var isInstalled: Bool {
        AILaunch.isAppInstalled(bundleID: bundleID)
    }

    /// Opens one thread by id.
    static func thread(_ id: String) -> String {
        "codex://threads/\(id)"
    }

    /// Opens the app's connections settings, where MCP servers and integrations live.
    static let connectionSettings = "codex://settings/connections"
}
