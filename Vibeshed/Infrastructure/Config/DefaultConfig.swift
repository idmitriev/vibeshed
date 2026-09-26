import Foundation

/// Written to `~/.config/vibeshed/config.yaml` when no config exists yet.
///
/// Deliberately minimal: it enables only modules backed by macOS itself (no
/// third-party apps assumed installed), none that need a privacy permission
/// beyond the Accessibility grant the picker hotkey already needs, and it
/// leaves the system default browser alone.
enum DefaultConfig {
    static let yaml = """
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
      application:    # launch, focus and quit apps
      system:         # lock, sleep, restart, appearance, screenshots, ...
      settings:       # System Settings panes
      audio:          # volume, mute, output/input devices
      processes:      # find processes by CPU/memory/port, kill on select
      math:           # calculator, unit and currency conversion
      timer:          # timers and reminders
      emoji:          # search emoji, copy on select
      websearch:      # web search fallback when nothing else matches
      self:           # open/reload this config, module status, quit

      # More modules — uncomment to enable:
      # clipboard:    # clipboard history (keeps copied text on disk)
      # window:       # window sizing/cycling (Accessibility + Screen Recording)
      # tiling:       # tiling grid per display (Accessibility)
      # browser:      # open browser tabs (Automation)
      # bookmark:     # browser bookmarks/history (Full Disk Access for Safari)
      # calendar:     # upcoming events (Calendars)
      # theme:        # palette themes across macOS and apps

    """
}
