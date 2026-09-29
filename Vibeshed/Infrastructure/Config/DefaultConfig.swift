import Foundation

/// Written to `~/.config/vibeshed/config.yaml` when no config exists yet.
///
/// Enables the modules backed by macOS itself plus one for each piece of software
/// found on this Mac (see `SoftwareIntegration`), and lists the rest commented out:
/// modules for software that isn't installed, and ones that need Calendars or Full
/// Disk Access. The permissions the enabled modules need are asked for right after
/// (see `PermissionSetup`). It leaves the system default browser alone.
enum DefaultConfig {
    struct Entry: Sendable {
        let moduleID: String
        let summary: String

        init(_ moduleID: String, _ summary: String) {
            self.moduleID = moduleID
            self.summary = summary
        }
    }

    /// Enabled on every Mac.
    static let builtInModules: [Entry] = [
        Entry("application", "launch, focus and quit apps"),
        Entry("system", "lock, sleep, restart, appearance, screenshots, ..."),
        Entry("settings", "System Settings panes"),
        Entry("audio", "volume, mute, output/input devices"),
        Entry("processes", "find processes by CPU/memory/port, kill on select"),
        Entry("performance", "CPU, memory, disk and network activity; opens Activity Monitor"),
        Entry("window", "move, resize and switch windows (Accessibility + Screen Recording)"),
        Entry("clipboard", "clipboard history, kept on disk (skips copied passwords)"),
        Entry("theme", "palette themes across macOS and apps"),
        Entry("math", "calculator, unit and currency conversion"),
        Entry("timer", "timers and reminders"),
        Entry("emoji", "search emoji, copy on select"),
        Entry("websearch", "web search fallback when nothing else matches"),
        Entry("self", "open/reload this config, module status, quit"),
    ]

    /// Listed commented out on every Mac, alongside integrations whose software is missing.
    static let optionalModules: [Entry] = [
        Entry("tiling", "tiling grid per display (Accessibility)"),
        Entry("menu", "the frontmost app's menu items (Accessibility)"),
        Entry("bookmark", "browser bookmarks/history (Full Disk Access for Safari)"),
        Entry("calendar", "upcoming events (Calendars)"),
        Entry("meetingPrep", "get ready for the next meeting (Calendars + Screen Recording)"),
    ]

    /// The config for a Mac where `detected` turned up.
    static func yaml(detected: [DetectedIntegration]) -> String {
        var lines = [header]
        lines += builtInModules.map { moduleLine($0.moduleID, $0.summary) }

        if !detected.isEmpty {
            lines += ["", "  # Found on this Mac:"]
            for integration in detected {
                lines.append(moduleLine(integration.moduleID, integration.summary))
                lines += integration.settings.map { "    " + $0 }
            }
        }

        let detectedIDs = Set(detected.map(\.moduleID))
        let missing = SoftwareIntegration.all
            .filter { !detectedIDs.contains($0.moduleID) }
            .map { Entry($0.moduleID, $0.summary) }
        lines += ["", "  # More modules — uncomment to enable:"]
        lines += (optionalModules + missing).map { moduleLine($0.moduleID, $0.summary, commented: true) }

        return lines.joined(separator: "\n") + "\n"
    }

    /// `  window:         # summary`, comments lined up in one column.
    private static func moduleLine(_ moduleID: String, _ summary: String, commented: Bool = false) -> String {
        let key = (commented ? "  # " : "  ") + moduleID + ":"
        let width = max(key.count + 1, 18)
        return key.padding(toLength: width, withPad: " ", startingAt: 0) + "# " + summary
    }

    private static let header = """
    # ~/.config/vibeshed/config.yaml
    # Vibeshed configuration — edits hot-reload on save.
    # Every option (and every module) is documented in config.example.yaml:
    # https://github.com/idmitriev/vibeshed/blob/main/config.example.yaml

    # Each entry is `combo` + `action` (run a Vibeshed action) or `remap`
    # (send another key combo). Optional `app: <bundle ID>` scopes it to one app.
    keybindings:
      - combo: "option+space"
        action: "app/togglePicker"

    # Keep the system default browser. Set to true to route links through
    # Vibeshed (rules + a browser chooser); see config.example.yaml.
    urlRouting:
      registerAsDefaultBrowser: false
      rules: []

    # A module loads only when its section is present. An empty section
    # enables it with default settings.
    modules:
    """
}
