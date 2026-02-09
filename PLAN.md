# What we are building

We are building a macOS launcher app with SwiftUI and Combine. 

The core functionality includes

- binding key-combos to actions
- handling URIs to trigger actions
- showing a searchable list of actions aka picker.
  
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

### Phase 1: Basic app setup

- [x] Create a SwiftUI app with a status bar icon and main window that can show a picker view.

### Phase 2: Core data structures and protocols

- [x] Create infrastructure - logging, event bus, config, permissions
- [x] Define protocols for modules and actions

### Phase 3: Typed configs for modules

- [ ] Application should use a single YAML config file located in ~/.config containing configuration for all the modules
- [ ] Create a typed config system that modules can use to define their configuration schemas
- [ ] Config file schanges should be propagated to modules and they should be able to react to them, for example by reloading data or updating actions

### Phase 4: Key-combos

- [ ] Implement key-combo binding system in the main app that can trigger actions based on user-defined key-combos
- [ ] Read key-combo configurations from the config file and set up the bindings accordingly
- [ ] Validate actions configured for key-combos to ensure they exist and can be executed
- [ ] Implement a caps-lock modifier mode that can be used to trigger actions when caps-lock is held down, and revert to normal behavior when released

### Phase 5: URI handling

- [ ] Implement a URI scheme for the app that can trigger actions based on URIs
- [ ] Set up the app to handle incoming URIs and dispatch them to the appropriate modules
- [ ] Set application as default browser to handle URL to chose browser or app to open in. 

### Phase 5: First module - window management

- [ ] Create a window management module that can list windows and perform actions like focus, move, resize
- [ ] Implement actions for cyclint between size stops in vertical and horizontal directions anchored to different edges of the screen. Steps should be configurable and support different screen sizes and units - pixels or percentage of the screen.
- [ ] Implement qurying for windows based on their title, application name, and other metadata
- [ ] Provide SwiftUI views for window actions in the picker
