# Vibeshed

A keyboard-driven macOS launcher built with SwiftUI. Control your Mac with keystrokes — manage windows, switch apps, search browser tabs, control Spotify, and more from a single floating picker.

## Features

**Launcher**
- Fuzzy-matched searchable picker with keyboard navigation and preview pane
- Usage-aware sorting that adapts to how you work
- Context-sensitive action boosting based on focused app, time of day, audio state
- Dynamic theming that shifts with your system appearance and vibe

**Window Management**
- Cycle window sizes anchored to screen edges, tile halves, maximize/restore
- Enlarge/shrink while keeping split position
- Focus windows by title or app name

**Applications & Browser**
- Launch, focus, or quit any app
- Search and switch browser tabs across Safari and Chromium browsers
- Browser bookmarks and most-visited sites
- Default browser with per-URL routing to specific browsers/profiles

**Productivity**
- Clipboard history with search and paste
- Timers and reminders
- Math expressions, unit conversions, currency conversion
- Calendar events with one-click join for Zoom/Meet
- Meeting prep: hide distractions and surface relevant docs

**Developer Tools**
- VSCode and JetBrains IDE project search
- iTerm session management and command execution
- GitHub repo/issue/PR search and notifications
- AI session search across Claude, ChatGPT, and Codex

**Media & Communication**
- Spotify search and playback control with OAuth
- System audio volume, mute, device selection, media keys
- Telegram chat quick-open

**System**
- Lock, sleep, restart, shutdown, toggle dark mode
- Empty trash, flush DNS, purge memory, screenshots
- App-scoped key remapping (remap keys per-application)
- Global and per-app key combo bindings
- Custom action aliases with keyword search

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9+ (for building from source)

## Installation

```bash
git clone https://github.com/idmitriev/vibeshed.git
cd vibeshed
make build
make run
```

The app runs as a menu bar item (no Dock icon). Use `make run-debug` to see logs in the terminal, or `make log` in a separate terminal for live OSLog streaming.

## Configuration

Configuration lives at `~/.config/vibeshed/config.yaml`. Copy the example to get started:

```bash
cp config.example.yaml ~/.config/vibeshed/config.yaml
```

See [config.example.yaml](config.example.yaml) for all available options including keybindings, module settings, URL routing rules, and action aliases.

The app watches the config file for changes and hot-reloads automatically.

## Modules

| Module | Description |
|--------|-------------|
| **Window** | Resize, move, tile, cycle, maximize/restore, focus windows |
| **Application** | Launch, focus, quit applications |
| **Browser** | Search/focus/close tabs in Safari and Chromium browsers |
| **Bookmark** | Browser bookmarks and most-visited URLs |
| **Clipboard** | Clipboard history with search, paste, and persistence |
| **Audio** | Volume, mute, device selection, media key control |
| **System** | Lock, sleep, restart, shutdown, appearance, screenshots |
| **Spotify** | Search artists/albums/playlists, playback control |
| **GitHub** | Search repos, issues, PRs; view notifications |
| **VSCode** | Search and open recent projects |
| **JetBrains** | Search and open IDE projects |
| **ITerm** | Session listing, command execution, new tabs |
| **AI** | Search Claude/ChatGPT/Codex sessions |
| **Telegram** | Quick-open configured chats and groups |
| **Calendar** | Upcoming events, join Zoom/Meet links |
| **MeetingPrep** | Prepare workspace for meetings |
| **Timer** | Set timers and reminders |
| **Math** | Arithmetic, unit/currency conversion |
| **Theme** | Dynamic appearance theming |
| **Self** | Open config, reload modules, view logs, quit |

Modules load only when their config section is present. Each module declares required permissions (accessibility, automation, etc.) and the app guides you through granting them.

## Key Bindings

Define bindings in the `keybindings:` config section. Each entry maps a key combo to an action or a key remap:

```yaml
keybindings:
  - combo: "capslock+space"
    action: "app/togglePicker"
  - combo: "capslock+1"
    action: "alias/Safari"
  - combo: "ctrl+h"
    remap: "left"
    app: "com.apple.Terminal"
```

Modifiers: `cmd`, `ctrl`, `option`/`alt`, `shift`, `capslock` (hyper), `space`. Mouse buttons: `mouse1`-`mouse5`.

## Architecture

- **Swift Package Manager** with `Package.swift` — no Xcode project required
- **Actor-based modules** for thread-safe concurrent action queries
- **SwiftUI** for picker UI, status bar, and module preview views
- **Combine** for debounced search input
- **NSPanel** subclass for the floating picker window
- **YAML config** with typed per-module schemas, validation, and hot-reload

## License

[MIT](LICENSE)
