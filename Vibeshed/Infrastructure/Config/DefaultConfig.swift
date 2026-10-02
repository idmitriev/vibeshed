import Foundation

/// Written to `~/.config/vibeshed/config.yaml` when no config exists yet.
///
/// Caps Lock is the modifier for the picker and window shortcuts. Enables the modules
/// backed by macOS itself plus one for each piece of software found on this Mac (see
/// `SoftwareIntegration`), and lists the rest commented out: modules for software that
/// isn't installed, and ones that need Calendars or Full Disk Access. The permissions
/// the enabled modules need are asked for right after (see `PermissionSetup`). It
/// leaves the system default browser alone.
enum DefaultConfig {
    struct Entry: Sendable {
        let moduleID: String
        let summary: String
        /// YAML lines for the module's section, indented relative to it.
        let settings: [String]

        init(_ moduleID: String, _ summary: String, settings: [String] = []) {
            self.moduleID = moduleID
            self.summary = summary
            self.settings = settings
        }

        init(_ integration: DetectedIntegration) {
            self.init(integration.moduleID, integration.summary, settings: integration.settings)
        }
    }

    /// 4pt from the screen edges and between windows.
    private static let padding = ["padding:", "  top: 4", "  bottom: 4", "  left: 4", "  right: 4", "  gap: 4"]

    /// Enabled on every Mac.
    static let builtInModules: [Entry] = [
        Entry("application", "launch, focus and quit apps"),
        Entry("system", "lock, sleep, restart, appearance, screenshots, ..."),
        Entry("settings", "System Settings panes"),
        Entry("audio", "volume, mute, output/input devices"),
        Entry("processes", "find processes by CPU/memory/port, kill on select"),
        Entry("performance", "CPU, memory, disk and network activity; opens Activity Monitor"),
        Entry(
            "window", "move, resize and switch windows (Accessibility + Screen Recording)",
            settings: padding
        ),
        Entry(
            "tiling", "tiling grid per display (Accessibility)",
            settings: [
                "defaultGrid:",
                "  columns: [1, 1]   # two side-by-side splits; weights, so [2, 1] is 2/3 + 1/3",
                "  rows: [1]",
            ] + padding
        ),
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
        Entry("menu", "the frontmost app's menu items (Accessibility)"),
        Entry("bookmark", "browser bookmarks/history (Full Disk Access for Safari)"),
        Entry("calendar", "upcoming events (Calendars)"),
        Entry("meetingPrep", "get ready for the next meeting (Calendars + Screen Recording)"),
    ]

    /// The config for a Mac where `detected` turned up.
    static func yaml(detected: [DetectedIntegration]) -> String {
        var lines = [header]
        lines += builtInModules.flatMap { sectionLines(for: $0) }

        if !detected.isEmpty {
            lines += ["", "  # Found on this Mac:"]
            lines += detected.flatMap { sectionLines(for: Entry($0)) }
        }

        let detectedIDs = Set(detected.map(\.moduleID))
        let missing = SoftwareIntegration.all
            .filter { !detectedIDs.contains($0.moduleID) }
            .map { Entry($0.moduleID, $0.summary) }
        lines += ["", "  # More modules — uncomment to enable:"]
        lines += (optionalModules + missing).map { moduleLine($0.moduleID, $0.summary, indent: "  ", commented: true) }

        return lines.joined(separator: "\n") + "\n"
    }

    /// A module's section under `modules:`, whose children sit `indent` deep: its key line
    /// and the settings below it.
    static func sectionLines(for entry: Entry, indent: String = "  ") -> [String] {
        [moduleLine(entry.moduleID, entry.summary, indent: indent)] + entry.settings.map { indent + indent + $0 }
    }

    /// `  window:         # summary`, comments lined up in one column.
    private static func moduleLine(
        _ moduleID: String,
        _ summary: String,
        indent: String,
        commented: Bool = false
    ) -> String {
        let key = indent + (commented ? "# " : "") + moduleID + ":"
        let width = max(key.count + 1, indent.count + 16)
        return key.padding(toLength: width, withPad: " ", startingAt: 0) + "# " + summary
    }

    private static let header = """
    # ~/.config/vibeshed/config.yaml
    # Vibeshed configuration — edits hot-reload on save.
    # Every option (and every module) is documented in config.example.yaml:
    # https://github.com/idmitriev/vibeshed/blob/main/config.example.yaml

    # Each entry is `combo` + `action` (run a Vibeshed action) or `remap`
    # (send another key combo). Optional `app: <bundle ID>` scopes it to one app.
    # Caps Lock works as a modifier: hold it and press the other key. That needs
    # Input Monitoring, which the setup window asks for.
    keybindings:
      - combo: "capslock+space"
        action: "app/togglePicker"

      # Focus the window beside the focused one
      - combo: "capslock+left"
        action: "window/focusLeft"
      - combo: "capslock+right"
        action: "window/focusRight"
      - combo: "capslock+up"
        action: "window/focusUp"
      - combo: "capslock+down"
        action: "window/focusDown"

      - combo: "capslock+m"
        action: "window/toggleMaximize"
      - combo: "capslock+p"
        action: "window/focusWindow"     # pick a window to focus

      # Cycle the focused window through 50% and 100% of the screen from an edge
      - combo: "capslock+w"
        action: "window/cycleTop"
      - combo: "capslock+a"
        action: "window/cycleLeft"
      - combo: "capslock+s"
        action: "window/cycleBottom"
      - combo: "capslock+d"
        action: "window/cycleRight"

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
