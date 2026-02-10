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

### Phase 6: Key-combos

- [ ] Implement key-combo binding system in the main app that can trigger actions based on user-defined key-combos
- [ ] Read key-combo (modifier+key or modifier1+modifier2+key) configurations from the config file and set up the bindings accordingly
- [ ] Validate actions configured for key-combos to ensure they exist and can be executed
- [ ] Implement a caps-lock and space as modifiers mode that can be used to trigger actions when key is held down
- [ ] Implement mouse button bindings, specifically for back and forward buttons on mx master mice

### Phase 7: URI handling

- [ ] Implement a URI scheme for the app that can trigger actions based on URIs
- [ ] Set up the app to handle incoming URIs and dispatch them to the appropriate modules
- [ ] Set application as default browser on start to handle URL to chose what browser/profile to open links with
- [ ] Configure what URLs to open immediately in some browser and what to send to the picker as actions based on the config file

### Phase 8: First module - window management

- [ ] Create a window management module that can list windows and perform actions like focus, move, resize
- [ ] Implement actions for cyclint between size stops in vertical and horizontal directions anchored to different edges of the screen. Steps should be configurable and support different screen sizes and units - pixels or percentage of the screen.
- [ ] Implement actions for maximizing, centering and minimizing windows. These actions have window as a parameter, provide focussed actions with focused window prefilled and actions that can be used from the picker with window selection.
- [ ] Implement actions for focusing windows based on their title, application name, and other metadata
- [ ] Provide SwiftUI views for window actions in the picker

### Phase 9: Proper picker UI

- [ ] Implement a beautiful animated searchable picker UI that can show actions provided by modules based on the current query - text, module and previously selected action that requires parameters. Picker should support keyboard navigation and selection.
- [ ] Implement a useful preview pane in the picker that can show additional information about the selected action
- [ ] Implement fuzzy searching and sorting of actions based on the query, usage frequency, and recency. Sorting should be done in a way that feels intuitive and surfaces the most relevant actions to the top.
- [ ] Implement a system for modules to provide dynamic action lists that can change even when the query is stable, for example based on external data or timers. The picker should update the displayed actions accordingly without disrupting the user's current selection or query.
