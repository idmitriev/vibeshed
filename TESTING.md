# Vibeshed Manual Testing Checklist

## Prerequisites

- macOS 14+ (Sonoma)
- Config file at `~/.config/vibeshed/config.yaml` (copy from `config.example.yaml`)
- Accessibility permission granted
- Input Monitoring permission granted
- Automation permission granted (for browser/Spotify/iTerm modules)
- Full Disk Access (for Safari bookmarks/history)

---

## 1. App Lifecycle

- [ ] App launches without crash
- [ ] Status bar icon appears in menu bar
- [ ] Single instance lock prevents second instance
- [ ] App starts on login when autostart is enabled
- [ ] App does not appear in Dock (LSUIElement)
- [ ] Quit from status bar menu terminates cleanly

## 2. Permissions

- [ ] Status bar shows check icon when all permissions granted
- [ ] Status bar shows warning icon when permissions are missing
- [ ] Missing permissions listed in status bar dropdown
- [ ] "Open System Preferences" links work for each permission type
- [ ] Modules requiring missing permissions do not load
- [ ] Modules load automatically after granting permissions (10s recheck)

## 3. Config

- [ ] App reads config from `~/.config/vibeshed/config.yaml`
- [ ] Invalid YAML shows error in logs, does not crash
- [ ] Invalid module config section logged, module skipped
- [ ] Valid config changes hot-reload without restart
- [ ] Modules react to config updates (e.g. changing volumeSteps)
- [ ] Removing a module section disables that module
- [ ] Adding a module section enables that module

## 4. Picker — Basic

- [ ] Picker opens with configured key-combo (default: capslock+space)
- [ ] Picker appears centered on active screen
- [ ] Picker is a floating panel above other windows
- [ ] Search field is focused on open
- [ ] Empty query shows default/recent actions
- [ ] Typing filters actions in real-time (150ms debounce)
- [ ] No results message shown for nonsense queries
- [ ] Escape closes picker
- [ ] Clicking outside picker closes it
- [ ] Picker state preserved when toggling off/on quickly
- [ ] Picker opens fast (< 200ms to first frame)

## 5. Picker — Navigation

- [ ] Arrow Up/Down navigates action list
- [ ] Selected item stays visible (auto-scroll)
- [ ] Return executes selected action
- [ ] Cmd+1 through Cmd+9 quick-select first 9 items
- [ ] Page Up/Down navigates by page
- [ ] Preview pane updates when selection changes
- [ ] Preview pane shows relevant info for selected action

## 6. Picker — Parameter Input

- [ ] Selecting action with parameters enters parameter input mode
- [ ] Selected action shown as pill in search field
- [ ] Parameter options listed correctly
- [ ] Typing filters parameter options
- [ ] Selecting parameter option executes action
- [ ] Backspace on empty field removes pill (goes back)
- [ ] Escape in parameter mode goes back to search
- [ ] Dynamic parameter options load correctly (e.g. window list)

## 7. Picker — Fuzzy Search & Sorting

- [ ] Fuzzy matching works (partial matches, typos)
- [ ] Frequently used actions rank higher
- [ ] Recently used actions rank higher
- [ ] Title matches score higher than subtitle/keyword matches
- [ ] Usage data persists across sessions (~/.config/vibeshed/usage.json)

## 8. Keyboard Layout Correction

- [ ] Wrong layout detection works (e.g. typing Russian on English layout)
- [ ] Layout correction hint shown in picker
- [ ] Actions still found when typing in wrong layout

## 9. Key-Combos

- [ ] Global key-combos work from any app (capslock+key)
- [ ] App-scoped key-combos only fire in configured app
- [ ] Key-combo with multiple modifiers (e.g. cmd+shift+p)
- [ ] Capslock as modifier (hyper key mode)
- [ ] Key-combos trigger correct actions
- [ ] Invalid action IDs in keybindings logged as errors

## 10. Key Remaps

- [ ] Global remaps work in all apps
- [ ] Per-app remaps only fire in configured app
- [ ] App-specific remaps override global remaps
- [ ] Mouse button remaps (mouse4/mouse5) work

## 11. URI Handling

- [ ] `vibeshed://picker?q=term` opens picker with query
- [ ] `vibeshed://{module}/{action}` triggers action directly
- [ ] HTTP/HTTPS URLs handled when registered as default browser
- [ ] URL routing rules match and open correct browser/profile
- [ ] Unmatched URLs show browser chooser picker
- [ ] Glob patterns work (*.github.com/*)
- [ ] Regex patterns work (/pattern/)
- [ ] No infinite loop when opening URLs (own bundle ID skipped)

## 12. Aliases

- [ ] Parameterless aliases enrich existing actions with keywords
- [ ] Parameterized aliases ({query}) create separate picker entries
- [ ] URL aliases open URLs in configured browser
- [ ] Directory aliases open folders in Finder
- [ ] Alias actions work from keybindings (alias.Name)
- [ ] Alias icons and subtitles display correctly

## 13. Dynamic Theme

- [ ] Theme intensity 0 = no theming
- [ ] Theme intensity > 0.3 = background tint
- [ ] Theme intensity > 0.6 = icon tint
- [ ] Theme intensity > 0.8 = glow effect
- [ ] Theme responds to system appearance changes
- [ ] Theme updates based on running apps / music

## 14. Contextual Actions

- [ ] Actions boosted based on focused app (e.g. window actions when many windows open)
- [ ] Time-of-day context affects scoring
- [ ] Audio state context affects scoring (mute actions when unmuted, etc.)
- [ ] Context captured once per picker show

---

## Module Testing

### 15. Window Module

- [ ] List windows from running apps
- [ ] Focus window action brings window to front
- [ ] Cycle left/right moves window through horizontal size stops
- [ ] Cycle top/bottom moves window through vertical size stops
- [ ] Maximize fills screen (respecting padding)
- [ ] Restore returns to pre-maximize size/position
- [ ] Center places window in screen center
- [ ] Tile left/right splits screen in halves
- [ ] Enlarge/shrink width changes window size by configured step
- [ ] Window actions work across multiple screens
- [ ] Window previews show screenshots with highlighted window

### 16. Application Module

- [ ] Lists installed applications
- [ ] Launch action opens app if not running
- [ ] Focus action brings running app to front
- [ ] Cycle-focus rotates through app windows
- [ ] Quit action terminates app
- [ ] Running apps show green indicator
- [ ] App icons display correctly
- [ ] Excluded bundle IDs not shown

### 17. Browser Module

- [ ] Lists open tabs from Safari
- [ ] Lists open tabs from Chrome (and other Chromium browsers)
- [ ] Focus tab action switches to tab
- [ ] Close tab action closes tab
- [ ] Open URL action opens in correct browser
- [ ] Tab cache refreshes after TTL
- [ ] Tab previews show titles and favicons

### 18. Bookmark Module

- [ ] Lists Safari bookmarks
- [ ] Lists Chrome bookmarks
- [ ] Most visited URLs shown with visit count
- [ ] Opening bookmark navigates to URL
- [ ] Bookmark cache refreshes at configured TTL
- [ ] minVisitCount filters low-visit history entries

### 19. System Module

- [ ] Lock screen action works
- [ ] Sleep action works
- [ ] Restart/Shutdown/Logout show confirmation or work correctly
- [ ] Toggle appearance switches dark/light mode
- [ ] Empty trash action works
- [ ] Screenshot actions (full, clipboard, interactive) work
- [ ] Flush DNS action works
- [ ] Purge memory action works
- [ ] Mission Control action works

### 20. Theme Module

- [ ] Set Dark/Light mode
- [ ] Set accent color
- [ ] Set wallpaper
- [ ] VSCode theme change
- [ ] JetBrains IDE theme change
- [ ] iTerm preset change
- [ ] Theme presets apply all settings at once

### 21. Audio Module

- [ ] Mute/unmute output
- [ ] Mute/unmute microphone
- [ ] Volume steps (25/50/75/100%) work
- [ ] Volume step increment/decrement
- [ ] Select output device
- [ ] Select input device
- [ ] Play/pause media
- [ ] Next/previous track
- [ ] Current volume shown in preview

### 22. Clipboard Module

- [ ] Clipboard history populated as items are copied
- [ ] Selecting history item pastes it (if pasteOnSelect)
- [ ] Clear history action works
- [ ] Exclude patterns filter sensitive items (tokens, API keys)
- [ ] History persists across app restarts
- [ ] Duplicate items moved to top (not duplicated)
- [ ] Dynamic updates when clipboard changes

### 23. Spotify Module

- [ ] Now playing track shown (when Spotify running)
- [ ] Search tracks/albums/artists/playlists (requires clientId)
- [ ] Play track/album/artist/playlist action works
- [ ] Add to liked songs action works
- [ ] Album art shown in preview
- [ ] Track info (artist, album, duration) in preview

### 24. GitHub Module

- [ ] Search repositories
- [ ] Search issues
- [ ] Search pull requests
- [ ] Open repo/issue/PR in browser
- [ ] Notifications shown (requires token)
- [ ] Repo avatars in preview
- [ ] Issue/PR status and labels in preview

### 25. VSCode Module

- [ ] Lists recent projects
- [ ] Open project in VSCode
- [ ] Supports variants (Cursor, Windsurf)
- [ ] Running projects show open indicator
- [ ] Project paths shown in subtitle

### 26. JetBrains Module

- [ ] Lists recent projects across JetBrains IDEs
- [ ] Open project in correct IDE
- [ ] Detects installed IDEs automatically
- [ ] Running projects show open indicator

### 27. iTerm Module

- [ ] Lists active sessions
- [ ] Focus session action switches to it
- [ ] Run command action executes in new tab
- [ ] Configured commands shown as actions
- [ ] Session CWD and job name shown

### 28. AI Module

- [ ] Lists Claude Code sessions
- [ ] Lists Claude Desktop sessions
- [ ] Lists Codex sessions
- [ ] Open session in browser/desktop app
- [ ] Resume Claude Code session in terminal
- [ ] Session titles and message previews shown

### 29. Telegram Module

- [ ] Configured chats listed as actions
- [ ] Open chat action launches Telegram with correct chat
- [ ] Saved Messages shortcut works
- [ ] Launch Telegram action works

### 30. Calendar Module

- [ ] Upcoming events listed within lookahead window
- [ ] Past events shown within lookbehind window
- [ ] Open event in Calendar.app
- [ ] Join Zoom/Meet from calendar event
- [ ] All-day events shown/hidden per config
- [ ] Declined events filtered per config

### 31. Zoom Module

- [ ] Configured meetings listed
- [ ] Join meeting action opens Zoom
- [ ] Start meeting action works
- [ ] Meeting keywords searchable

### 32. Meeting Prep Module

- [ ] Prep actions appear before meetings (within prepWindowMinutes)
- [ ] Prep action hides irrelevant windows
- [ ] Relevant meeting URLs/docs opened
- [ ] Meeting info shown in preview

### 33. Timer Module

- [ ] Set timer with preset durations
- [ ] Set custom duration timer
- [ ] Timer notification fires when complete
- [ ] Cancel timer action works
- [ ] Clear completed timers
- [ ] Set reminder for specific date/time
- [ ] Active timers shown in picker

### 34. Math Module

- [ ] Arithmetic expressions evaluated (2+2, 3*4.5)
- [ ] Unit conversions (10km to miles, 100F to C)
- [ ] Currency conversions (100 USD to EUR)
- [ ] Percentage calculations (15% of 200)
- [ ] Base conversions shown for integers (hex/bin/oct)
- [ ] Copy result to clipboard on select
- [ ] Math actions boosted when query is expression

### 35. Self Module

- [ ] Open config file in editor
- [ ] Open config directory in Finder
- [ ] Reload config action reloads all modules
- [ ] Module status shows loaded/failed modules
- [ ] Open logs action works
- [ ] Quit app action works

---

## Edge Cases

- [ ] Very long queries don't crash or freeze
- [ ] Rapid typing/deleting doesn't cause race conditions
- [ ] Opening picker during app launch doesn't crash
- [ ] Multiple screens: picker appears on active screen
- [ ] Screen resolution change doesn't break layout
- [ ] Config file deleted while running: app continues with last valid config
- [ ] Module providing many actions (100+): picker stays responsive
- [ ] Concurrent key-combo and picker interaction
- [ ] Actions that fail: error shown, app doesn't crash
- [ ] Network-dependent modules (GitHub, Spotify) handle offline gracefully
- [ ] Browser not running: browser module actions unavailable gracefully
- [ ] Rapid picker toggle (open/close/open) doesn't leave ghost windows

---

## Performance

- [ ] Picker opens in < 200ms
- [ ] Search results appear within 300ms of typing (including 150ms debounce)
- [ ] Action execution feels instant (< 100ms for local actions)
- [ ] Memory usage stays stable over extended use
- [ ] CPU usage near zero when idle
- [ ] No visible jank in animations
