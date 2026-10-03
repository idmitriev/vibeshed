import AppKit

/// Third-party software a module works with. The config written on first launch
/// enables the module when any of its probes finds something on this Mac.
struct SoftwareIntegration: Sendable {
    let moduleID: String
    /// The trailing comment on the module's line in config.yaml.
    let summary: String
    let probes: [SoftwareProbe]
}

/// One thing to look for: an installed app, or a CLI or data directory.
struct SoftwareProbe: Sendable {
    enum Target: Sendable {
        case app(bundleID: String)
        /// A leading `~` expands to the home directory.
        case path(String)
    }

    let target: Target
    /// How the welcome window names what was found.
    let name: String
    /// Config key that gets the matched path when this is the first probe to match,
    /// for software the module can't find on its own.
    var pathSetting: String?

    static func app(_ bundleID: String, _ name: String) -> SoftwareProbe {
        SoftwareProbe(target: .app(bundleID: bundleID), name: name)
    }

    static func path(_ path: String, _ name: String, setting: String? = nil) -> SoftwareProbe {
        SoftwareProbe(target: .path(path), name: name, pathSetting: setting)
    }
}

/// A module the first-launch config enables, and what turned up for it.
struct DetectedIntegration: Sendable, Equatable {
    let moduleID: String
    let summary: String
    /// Names of what was found, without repeats, in probe order: "VS Code", "Cursor".
    let software: [String]
    /// YAML lines for the module's section.
    let settings: [String]
}

/// The system as detection sees it. Tests substitute their own.
struct SoftwareEnvironment: Sendable {
    var isAppInstalled: @Sendable (_ bundleID: String) -> Bool
    var fileExists: @Sendable (_ path: String) -> Bool
    var homeDirectory: String

    /// LaunchServices can still list an app that was deleted, so the bundle must exist too.
    static let live = SoftwareEnvironment(
        isAppInstalled: { bundleID in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                .map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        },
        fileExists: { FileManager.default.fileExists(atPath: $0) },
        homeDirectory: NSHomeDirectory()
    )

    /// This environment, also counting `bundleIDs` as installed: apps that were just put
    /// in place, before LaunchServices has picked them up.
    func adding(apps bundleIDs: Set<String>) -> SoftwareEnvironment {
        var environment = self
        let isAppInstalled = isAppInstalled
        environment.isAppInstalled = { bundleIDs.contains($0) || isAppInstalled($0) }
        return environment
    }

    func expand(_ path: String) -> String {
        path.hasPrefix("~/") ? homeDirectory + path.dropFirst() : path
    }
}

// MARK: - Detection

extension SoftwareIntegration {
    /// The integrations whose software is on this Mac, in `integrations` order.
    static func detect(
        in environment: SoftwareEnvironment,
        among integrations: [SoftwareIntegration] = all
    ) -> [DetectedIntegration] {
        integrations.compactMap { $0.detect(in: environment) }
    }

    /// The modules whose software is on this Mac.
    static func detectedModuleIDs(in environment: SoftwareEnvironment = .live) -> Set<String> {
        Set(detect(in: environment).map(\.moduleID))
    }

    /// The integrations found in `environment` that weren't among `before` (module IDs
    /// detected earlier): what an install just added.
    static func added(since before: Set<String>, in environment: SoftwareEnvironment) -> [DetectedIntegration] {
        detect(in: environment).filter { !before.contains($0.moduleID) }
    }

    func detect(in environment: SoftwareEnvironment) -> DetectedIntegration? {
        let matches = probes.filter { $0.isPresent(in: environment) }
        guard let first = matches.first else { return nil }

        var software: [String] = []
        for match in matches where !software.contains(match.name) {
            software.append(match.name)
        }
        var settings: [String] = []
        if let key = first.pathSetting, case let .path(path) = first.target {
            settings.append("\(key): \(Self.quoted(environment.expand(path)))")
        }
        return DetectedIntegration(moduleID: moduleID, summary: summary, software: software, settings: settings)
    }

    private static func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

extension SoftwareProbe {
    func isPresent(in environment: SoftwareEnvironment) -> Bool {
        switch target {
        case let .app(bundleID): environment.isAppInstalled(bundleID)
        case let .path(path): environment.fileExists(environment.expand(path))
        }
    }
}

// MARK: - Catalog

extension SoftwareIntegration {
    /// Every integration, in the order their sections are written to config.yaml.
    static let all: [SoftwareIntegration] = [
        SoftwareIntegration(
            moduleID: "browser",
            summary: "search and switch browser tabs (Automation)",
            probes: BrowserRegistry.appleScriptCapable.map { .app($0.bundleID, $0.name) }
        ),
        SoftwareIntegration(
            moduleID: "homebrew",
            summary: "search, install and upgrade Homebrew packages",
            probes: [
                .path("/opt/homebrew/bin/brew", "Homebrew"),
                // Intel Macs. The module defaults to the Apple silicon prefix above.
                .path("/usr/local/bin/brew", "Homebrew", setting: "brewPath"),
            ]
        ),
        SoftwareIntegration(
            moduleID: "anthropic",
            summary: "Claude Code and Claude Desktop sessions",
            probes: [
                .app(AnthropicDeeplink.bundleID, "Claude"),
                .path("~/.claude", "Claude Code"),
                .path("/opt/homebrew/bin/claude", "Claude Code"),
                .path("/usr/local/bin/claude", "Claude Code"),
            ]
        ),
        SoftwareIntegration(
            moduleID: "openai",
            summary: "Codex sessions from the ChatGPT app and the Codex CLI",
            probes: [
                .app(OpenAIDeeplink.bundleID, "ChatGPT"),
                .path("~/.codex", "Codex"),
                .path("/opt/homebrew/bin/codex", "Codex"),
                .path("/usr/local/bin/codex", "Codex"),
            ]
        ),
        SoftwareIntegration(
            moduleID: "vscode",
            summary: "recent VS Code, Cursor and Windsurf projects",
            probes: [
                .app("com.microsoft.VSCode", "VS Code"),
                .app("com.microsoft.VSCodeInsiders", "VS Code Insiders"),
                .app("com.vscodium", "VSCodium"),
                .app("com.todesktop.230313mzl4w4u92", "Cursor"),
                .app("com.exafunction.windsurf", "Windsurf"),
            ]
        ),
        SoftwareIntegration(
            moduleID: "jetbrains",
            summary: "recent JetBrains IDE projects",
            probes: [
                .app("com.jetbrains.intellij", "IntelliJ IDEA"),
                .app("com.jetbrains.intellij.ce", "IntelliJ IDEA CE"),
                .app("com.jetbrains.pycharm", "PyCharm"),
                .app("com.jetbrains.pycharm.ce", "PyCharm CE"),
                .app("com.jetbrains.WebStorm", "WebStorm"),
                .app("com.jetbrains.goland", "GoLand"),
                .app("com.jetbrains.rustrover", "RustRover"),
                .app("com.jetbrains.CLion", "CLion"),
                .app("com.jetbrains.rider", "Rider"),
                .app("com.jetbrains.PhpStorm", "PhpStorm"),
                .app("com.jetbrains.rubymine", "RubyMine"),
                .app("com.jetbrains.datagrip", "DataGrip"),
            ]
        ),
        SoftwareIntegration(
            moduleID: "zed",
            summary: "recent Zed workspaces",
            probes: [.app("dev.zed.Zed", "Zed"), .app("dev.zed.Zed-Preview", "Zed Preview")]
        ),
        SoftwareIntegration(
            moduleID: "iterm",
            summary: "iTerm sessions, new tabs and commands (Automation)",
            probes: [.app(ITermTarget.bundleID, "iTerm")]
        ),
        SoftwareIntegration(
            moduleID: "ghostty",
            summary: "Ghostty terminals, new tabs and commands (Automation)",
            probes: [.app(GhosttyApp.bundleID, "Ghostty")]
        ),
        SoftwareIntegration(
            moduleID: "spotify",
            summary: "playback controls and what's playing (Automation)",
            probes: [.app(SpotifyManager.bundleID, "Spotify")]
        ),
        SoftwareIntegration(
            moduleID: "telegram",
            summary: "open Telegram, Saved Messages and chats you list here",
            probes: [.app(TelegramModule.bundleID, "Telegram")]
        ),
        SoftwareIntegration(
            moduleID: "zoom",
            summary: "start and join Zoom meetings",
            probes: [.app(ZoomManager.bundleID, "Zoom")]
        ),
        SoftwareIntegration(
            moduleID: "github",
            summary: "search GitHub repos, issues and pull requests",
            probes: [
                .path("/opt/homebrew/bin/gh", "GitHub CLI"),
                .path("/usr/local/bin/gh", "GitHub CLI"),
                .app("com.github.GitHubClient", "GitHub Desktop"),
            ]
        ),
    ]
}
