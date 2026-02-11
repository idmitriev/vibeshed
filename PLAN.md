# What we are building

We are building a macOS launcher app with SwiftUI and Combine. 

The core functionality includes

- binding key-combos to actions
- handling URIs to trigger actions
- showing a searchable list of actions
  
Actions are provided by modules, for example

- window module that does window moving/resizing and listing
- application list module that can launch or focus application windows.

## Architecture

The main app is responsible for showing the picker, managing its state, handling key-combos and URIs, and dispatching actions to modules. It watches for config file changes and reloads modules when needed.

Main app provides infrastructure features such as logging, event bus, requesting permissions, and so on.

Modules own their state and provide actions based on picker query. Providing and running actions is happening outside of the main thread, so that UI is not blocked.

Actions can have parameters, options for parameters can be provided by modules as well. Also modules provide list item and preview SwiftUI views for actions. Actions can trigger picker's state changes, for example picker query.

Sorting and rating actions is done by modules AND picker since it knows about usage and recency. Actions lists can change dynamically even when the query is stable.

## Implementations phases

### Phase 1: Basic app setup (DONE)

- [x] Create a SwiftUI app with a status bar icon and main window that can show a picker view.
- [x] Setup SPM for the project and create a module structure for the main app and modules

### Phase 2: Core data structures and protocols (DONE)

- [x] Create infrastructure - logging, event bus, config, permissions
- [x] Define protocols for modules and actions

### Phase 3: Tooling for development  (DONE)

- [x] Set up a swiftlint and swiftformat configuration for the project to maintain code quality and consistency
- [x] Set up XCUI tests for the picker UI. Tests should cover basic functionality like showing the picker, searching for actions, and executing actions.

### Phase 4: Typed configs for modules (DONE)

- [x] Application should use a single YAML config file located in ~/.config containing configuration for all the modules
- [x] Create a typed config system that modules can use to define their configuration section schemas and validate them
- [x] Log config validation errors and provide feedback to the user about what needs to be fixed in the config file. Do not load module if config is invalid.
- [x] Valid config file changes should be propagated to modules and they should be able to react to them, for example by reloading data or updating actions

### Phase 5: Permissions handling (DONE)

- [x] Implement a permissions manager that can request and manage permissions needed by modules: accessability, screen recording, automation, input monitoring, file system access, etc
- [x] Modules should be able to declare the permissions they need, and the main app should handle requesting those permissions from the user and notifying modules of the permission status
- [x] Prevent modules from loading if they require permissions that have not been granted, and provide feedback to the user about which permissions are needed and how to grant them
- [x] Add an entitlements file to the project with the necessary permissions for the app to function properly

### Phase 6: Key-combos (DONE)

- [x] Implement key-combo binding system in the main app that can trigger actions based on user-defined key-combos
- [x] Read key-combo (modifier+key or modifier1+modifier2+key) configurations from the config file and set up the bindings accordingly
- [x] Validate actions configured for key-combos to ensure they exist and can be executed
- [x] Implement a caps-lock and space as modifiers mode that can be used to trigger actions when key is held down
- [x] Implement mouse button bindings, specifically for back and forward buttons on mx master mice

### Phase 7: URI handling (DONE)

- [x] Implement a URI scheme (vibeshed://) for the app that can trigger actions
- [x] On start set application as default browser on start to handle URL to chose what browser/profile to open links with
- [x] Allow configuring what URLs to open immediately in browser/profile and what to send to the picker as actions based on the config file

### Phase 8: First module - window management (DONE)

- [x] Create a window management module that can list windows and perform actions like focus, move, resize
- [x] Implement actions for cycling between size stops in vertical and horizontal directions anchored to different edges of the screen. Steps should be configurable and support different screen sizes and units - pixels or percentage of the screen.
- [x] Implement actions for maximizing, centering and minimizing windows
- [x] Implement actions for tiling 2 windows in vertical and horizontal halves of the screen
- [x] Actions have window as a parameter, provide focussed actions with focused window prefilled and actions that can be used from the picker with window selection.
- [x] Implement actions for focusing windows based on their title, application name, and other metadata
- [x] Provide SwiftUI views for window actions in the picker

### Phase 9: Single instance lock (DONE)

- [x] Implement a single instance lock to prevent multiple instances of the app from running at the same time

### Phase 10: Proper picker UI (DONE)

- [x] Implement a beautiful animated searchable picker UI that can show actions provided by modules based on the current query - text, module and previously selected action that requires parameters. Picker should support keyboard navigation and selection.
- [x] Implement action parameter binding in the picker, so that when an action is selected, its parameters can be filled in using the query or other input methods. For example, if an action requires a window parameter, the picker can show a list of windows to choose from when the action is selected. Change action protocol if required to support this. This is a crucial part a superb solution is required here. For some actions parameter options can be provided upfront, but some will require dynamic fetching based on the query or other parameters.
- [x] Implement a useful preview pane in the picker that can show additional information about the selected action
- [x] Implement fuzzy searching and sorting of actions based on the query, usage frequency, and recency. Sorting should be done in a way that feels intuitive and surfaces the most relevant actions to the top.
- [x] Implement a system for modules to provide dynamic action lists that can change even when the query is stable, for example based on external data or timers. The picker should update the displayed actions accordingly without disrupting the user's current selection or query

### Phase 11: Application module (DONE)

- [x] Create an application module that can list applications and their windows, and perform actions like launch, focus, quit
- [x] Implement actions for launching applications, cycle-focusing existing windows, and quitting applications
- [x] Provide SwiftUI views for application actions in the picker, showing application icons and window previews
- [x] Implement actions for focusing windows based on their title, application name, and other metadata

### Phase 12: Browser module

- [ ] Implement a browser module that can list, focus, open and close tabs in safari and chrome
- [ ] Provide SwiftUI views for tab actions in the picker, showing tab titles and favicons
- [ ] Implement actions for focusing tabs based on their title, URL, and other metadata

### Phase 13: Favourites module

- [ ] Create a favourites module that can list user-defined favourite actions and perform them
- [ ] Favourites defined in config and can be assigned aliases for quick searching

### Phase 14: Common helpers

- [ ] Implement common windows helper for listing and focusing windows that can be used by application and window modules
- [ ] Implement common browsers helper for listing browsers with profiles, open tabs and opening URLs in them that can be used by the URI handling and application modules

### Phase 15: System module

- [ ] Create a system module that can perform system actions like sleep, shutdown, restart, lock screen, etc
- [ ] Implement actions for lock, reboot, shutdown, toggle appearance, empty trash, take screenshots, flush DNS, purge memory
- [ ] Provide SwiftUI views for system actions in the picker

### Phase 16: Audio module

- [ ] Create an audio module that can control system audio
- [ ] Implement actions for mute/unmute, mic mute/unmute, volume 20%/50%/80%, next/previous track, play/pause, select input/output devices
- [ ] Provide SwiftUI views for audio actions in the picker, showing current volume levels and track information

### Phase 17: Clipboard module

- [ ] Create a clipboard module that can manage clipboard history and perform actions on clipboard items
- [ ] Implement actions for listing clipboard history, selecting an item to paste, clearing history,

### Phase 18: Spotify module

- [ ] Create a Spotify module for searching artists/albums/playlists
- [ ] Implement actions for searching Spotify and starting playback of artists, albums, playlist and tracks
- [ ] Provide SwiftUI views for Spotify actions in the picker, showing album art and track information

### Phase 19: Github module

- [ ] Create a Github module for searching pull requests, issues and repositories
- [ ] Implement actions for searching Github and opening pull requests, issues and repositories in the browser
- [ ] Provide SwiftUI views for Github actions in the picker, showing repository avatars and issue/PR information