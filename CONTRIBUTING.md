# Contributing to Vibeshed

Thanks for taking a look. Vibeshed is a small personal project built in the open, so contributions are welcome but the bar is "fits the vision" — read the [Goals and Non-goals](README.md#goals) before opening a substantial PR.

## Quick start

```bash
git clone https://github.com/idmitriev/vibeshed.git
cd vibeshed
make build
make run-debug   # logs in this terminal
```

Config lives at `~/.config/vibeshed/config.yaml`. Copy `config.example.yaml` to get started.

Requirements: macOS 14+, Swift 5.9+, Xcode command-line tools.

## Project layout

```
Vibeshed/
  App/             VibeshedApp, AppDelegate, status bar
  Panel/           Floating NSPanel + controller
  Picker/          Picker state machine, fuzzy match, parameter binding
  Infrastructure/  Logging, EventBus, Config, Permissions, KeyCombo, URI, Windows, Browsers, Aliases
  Modules/         One folder per module (Window, Application, Browser, Spotify, …)
```

Every module is an actor conforming to `Module` / `ModuleConfigurable`. Actions are `Sendable` value types crossing actor boundaries.

## Adding a module

1. Create `Vibeshed/Modules/MyThing/` with `MyThingModule.swift` and `MyThingConfig.swift`.
2. Conform to `ModuleConfigurable`. Declare `requiredPermissions` if any.
3. Register in `ModuleRegistry`.
4. Add a section to `config.example.yaml`. Modules load only when their config section is present.
5. Provide SwiftUI list and preview views via the module's `view(for:)` if your actions need richer rendering.

## Style

- `make lint` (SwiftLint, xcode reporter). `make lint-fix` for autofixes.
- `.swiftformat` is enforced — run your editor's SwiftFormat integration.
- Function bodies cap at 100 lines (SwiftLint). Split action builders into helpers.
- No new dependencies without discussion. We have two (KeyboardShortcuts, Yams). Keep it small.

## Testing

- `swift test` runs the test suite.
- XCUI tests live in `VibeshedUITests/`. They cover picker show/search/execute and permission flows.
- For features that touch system state (audio, windows, accessibility), test by hand with `make run-debug` and `make log` in a second terminal. Add a checklist entry to `TESTING.md` if appropriate.

## Pull requests

- One change per PR. Keep diffs reviewable.
- Match the existing commit style: lowercase, prefix with `feat:` / `fix:` / `chore:` / `refactor:`.
- Update `PLAN.md` if your work completes a phase item.
- Don't bump version numbers — releases are tagged manually.

## Reporting issues

Include: macOS version, Vibeshed version (`Vibeshed → About` or git SHA), the relevant slice of `config.yaml`, and the output of `make log` while reproducing.

## License

By contributing, you agree your work is licensed under the [MIT License](LICENSE).
