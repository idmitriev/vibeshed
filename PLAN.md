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

### Phase 12: Browser module (DONE)

- [x] Create a browser module that can list, focus, open and close tabs in safari and chrome
- [x] Implement action for searchin and opening tabs in safari and chrome based on their title, URL and other metadata
- [x] Provide SwiftUI views for tab actions in the picker, showing tab titles and favicons
- [x] Implement actions for focusing tabs based on their title, URL, and other metadata

### Phase 13: Favourites module (DONE)

- [x] Create a favourites module that can list user-defined favourite actions configured and run them
- [x] Implement action for running favourite actions
- [x] Allow pasing parameters for favourite actions, for example a search query for google search
- [x] Favourites defined in config and can be assigned aliases for quick searching

### Phase 14: Common helpers (DONE)

- [x] Implement common windows helper for listing and focusing windows that can be used by application and window modules
- [x] Implement common browsers helper for listing browsers with profiles, open tabs and opening URLs in them that can be used by the URI handling and application modules
- [x] Based on future phases evaluate if more common helpers are needed for other domains like audio, system, spotify, github, etc and implement them as well

### Phase 15: System module (DONE)

- [x] Create a system module that can perform system actions like sleep, shutdown, restart, lock screen, etc
- [x] Implement actions for lock, reboot, shutdown, toggle appearance, empty trash, take screenshots (with params for cliboard/file and target), flush DNS, purge memory
- [x] Provide SwiftUI views for system actions in the picker

### Phase 16: Audio module (DONE)

- [x] Create an audio module that can control system audio
- [x] Implement actions for mute/unmute, mic mute/unmute, volume 20%/50%/80%, next/previous track, play/pause, select specific input/output devices
- [x] Provide SwiftUI views for audio actions in the picker, showing current volume levels and track information

### Phase 17: Clipboard module (DONE)

- [x] Create a clipboard module that can manage clipboard history and perform actions on clipboard items
- [x] Implement actions for listing clipboard history, selecting an item to paste, clearing history,

### Phase 18: Spotify module (DONE)

- [x] Create a Spotify module for searching artists/albums/playlists
- [x] Implement actions for searching Spotify and starting playback of artists, albums, playlist and tracks
- [x] Provide SwiftUI views for Spotify actions in the picker, showing album art and track information

### Phase 19: Github module (DONE)

- [x] Create a Github module for searching pull requests, issues and repositories
- [x] Implement actions for searching Github and opening pull requests, issues and repositories in the browser
- [x] Provide SwiftUI views for Github actions in the picker, showing repository avatars and issue/PR information

### Phase 20: VSCode module (DONE)

- [x] Create a VSCode module for searching and opening projects VSCode
- [x] Implement actions for searching VSCode projects based on their name and path and opening  them in VSCode
- [x] Provide SwiftUI views for VSCode actions in the picker, showing project names and paths

### Phase 21: Iterm module (DONE)

- [x] Create an Iterm module for searching and opening sessions or running commands in Iterm
- [x] Implement actions for searching Iterm sessions based on their name and running commands in Iterm
- [x] Provide SwiftUI views for Iterm actions in the picker, showing session names

### Phase 22: AI session module (DONE)

- [x] Create an AI module that can search and open AI sessions in the browser on desktop apps
- [x] Implement actions for searching sessions in chatgpt, claude and opening them in the browser or claude-desktop/chatgpt-desktop/codex-deskop apps if they are installed
- [x] Provide SwiftUI views for AI chat actions in the picker, showing session titles and latest message previews

### Phase 23: Telegram module (DONE)

- [x] Create a Telegram module that can search and open chats and groups in the Telegram desktop app
- [x] Research if Telegram provides any APIs or AppleScript support for searching and opening chats/groups. If not, implement a solution using accessibility APIs to interact with the Telegram desktop app UI to perform these actions. If nothing works, read chats and groups ids from config file
- [x] Implement actions for searching chats and groups in Telegram based on their name and opening them in the Telegram desktop app
- [x] Provide SwiftUI views for Telegram chat actions in the picker, showing chat/group names

### Phase 24: Self module (DONE)

- [x] Create a self module that can show actions related to the app itself, such as opening config file, reloading modules, viewing logs, exiting the app, etc
- [x] Implement actions for opening the config file in the default editor, reloading modules, viewing logs in the picker or opening log file, exiting the app, etc
- [x] Provide SwiftUI views for self actions in the picker, showing relevant information like log previews or config file path

### Phase 25: Contextual actions (DONE)

- [x] Provide actions with rank boost or filter them based on context: running/focused application, current window sizes, system state, time of day, date, current volume, media playing, and overall vibe
- [x] SystemContext captures system state snapshot when picker opens (focused app, running apps, time, audio state, window count, focused window title)
- [x] ContextualScorer applies additive boosts [-0.15, +0.15] based on context signals: focused app → module affinity, Spotify running state, time of day, audio mute/volume state, visible window count
- [x] Context captured once per picker show, reused across queries for that session

### Phase 26: Dynamic theme (DONE)

- [x] Implement a dynamic theming system that can change the app's appearance based on current system theme/appearance, open apps color schemes, music playing and overal vibe. This can include changing colors, fonts, and other visual elements of the app to create a more immersive and personalized user experience.
- [x]  Allow user to configure how dramatic theme changes are from subtle accent color adjustment (0) to full on winamp-style (1) theming based on the vibe

### Phase 27: Autostart and permissions cleanup (DONE)

- [x] Implement an autostart mechanism to launch the app on system startup, add item to status bar menu to enable/disable autostart
- [x] Cleanup permissions UI by showing a status bar menu item with check icon if all permissions are granted and warning icon with a dropdown of missing permissions if not. Also add an option to open the permissions tab in system preferences for each missing permission, remove all other modals asking for permissions and just show the status in the menu bar

### Phase 28: Debug logging and error handling (DONE)

- [x] Add debug logging throughout the app to help with troubleshooting and understanding app behavior. Logs should be categorized and have different levels (info, warning, error) for better filtering.

### Phase 29: Open URL picker action (DONE)

- [x] Register as URL handler application on start
- [x] On url open request show picker with browser/profile options
- [x] For configured URL patterns open configured browser/profile directly without showing the picker

### Phase 30: More window actions (DONE)

- [x] Enlarge/shrink window keeping split/anchor action
- [x] Implement an action for maximizing and restoring windows that can toggle between maximized and previous size/position states.

### Phase 31: Action aliasing

- [x] Implement action aliasing in the config file to allow users to define custom aliases for actions. This will make it easier for users to search for and remember actions by using their own terminology.

### Phase 32 : App scoped key-combos/remaps (DONE)

- [x] Implement a system for app scoped key-combos or remaps that can trigger actions only when a specific application is focused.
- [x] Implement key remapping functionality that allows users to remap keys or key-combos to different actions on a per-application basis.

### Phase 33: Better previews (DONE)

- [x] Make preview layout more spread out using all available space and not centered like now
- [x] Implement better previews for actions in the picker, showing more relevant information and visuals to help users understand what the action does and what parameters it requires
- [x] For windows show screenshot previews with highlighted focused window
- [x] For browser tabs show website favicons and titles
- [x] For spotify show album art and track info
- [x] For github show repo avatars and issue/PR info, etc

### Phase 35: Navigation in picker (DONE)

- [x] Implement navigation in the picker to allow users to easily go back from action parameter selection to the main action list, show selected action as a pill in the query that can be removed to go back, etc
- [x] Support paging in the action list when there are many actions available
- [x] Support activating list items with cmd+number hotkeys for the first 9 items in the list

### Phase 36: Jetbrains module (DONE)

- [x] Create a Jetbrains IDEs module for searching and opening projects in Jetbrains IDEs
- [x] Implement actions for searching Jetbrains IDE projects based on their name and path and opening

### Phase 37: Zoom module (DONE)

- [x] Create a zoom module for searching and joining zoom meetings
- [x] Implement actions for searching zoom meetings based on their title and joining them in the zoom, action for starting meetings as well

### Phase 38: UI Polish (DONE)

- [x] Make UI more readable by increasing font size, improving contrast, and adding more spacing between elements
- [x] Make icons in preview larger
- [x] Add animations for picker opening/closing, action selection, execution and other interactions to make the app feel more responsive and enjoyable to use

### Phase 39: Functional polish part 1

- [x] maximize/restore action should restore to window size/position before maximizing, not to configured size/position, remove config options for maximize size/position

### Phase 40: Functional polish part 2

- [x] make sure we can remap key combos OS-wide not just in specific apps, rename appRemaps config section to keyRemaps

### Phase 41: Functional polish part 3

- [x] remove number of items in picker list footer
- [x] dont show cover art in spotify picker items - just show player app/spotify icon, move cover art to the bottom of preview pane
- [x] show green open indicators for apps like for idea projects for launch or foucus app actions, also check if the same is possible for vscode projects

### Phase 42: Functional polish part 4

- [x] make sure there is configuration for all module in config example yaml

### Phase 43: Functional polish part 5

- [x] make sure browser profiles are supported in url routing rules

### Phase 44: Functional polish part 6

- [x] add actions for adding to liked songs in spotify module for now playing track

### Phase 45: Functional polish part 7

- [x] make sure aliases can open URLs in browsers, directories in finder
 
### Phase 46: Calendar module (DONE)

- [x] Create a calendar module for searching and opening calendar events in the browser or calendar apps
- [x] Implement actions for searching calendar events based on their title and opening them in browser, calendar.app, zoom or google meet in browser

### Phase 47: Prepare for meeting module (DONE)

- [x] Create a prepare for meeting module that can help users quickly prepare for meetings by showing relevant information and actions based on calendar events, meeting titles, and other metadata
- [x] Implement action that hides all windows except the one relevant for the meeting, open relevant documents, show meeting agenda and participants, and other relevant information in the picker preview to help users quickly get ready for meetings

### Phase 48: Browser bookmark actions (DONE)
- [x] Implement a system for browser bookmark actions that can show bookmarks from browsers and open them directly from the picker. This can include showing bookmark folders and allowing users to navigate through them in the picker to find the bookmark they want to open.
- [x] Implement bookmark actions for Safari and Chrome at least, showing bookmark titles and favicons in the picker previews
- [x] Implement actions for most visited URL in browser history as well, showing visit count and last visited date in the previews, limit number of these actions to some configurable number to prevent overwhelming the picker with too many options

### Phase 49: Theming actions

- [x] Implement actions that can set system apperance like wallpaper/accent colors, light/dark mode, cursor color, and other settings
- [x] Implement actions to set theme in apps: VSCode, Jetbrains IDEs, iTerm, Telegram, Codex desktop, Claude desktop, ChatGPT desktop, Chrome
- [x] Implement 3 themes

### Phase 50: Wrong keyboard layout detection and switching

- [x] Implement a system for detecting when the user is typing in the wrong keyboard layout and automatically switching to the correct layout based on the user's input. This can help prevent frustration and improve typing efficiency for users who frequently switch between different keyboard layouts.

### Phase 51: Performance optimizations (DONE)

- [x] Profile the app's performance and identify any bottlenecks or areas for improvement. Implement optimizations to ensure that the app runs smoothly and efficiently, even with a large number of actions
- [x] Add performance logging for profiling actions and rendering
- [x] Introduce in- or inter- module caching

### Phase 52: Timers/reminders module (DONE)

- [x] Create a timers and reminders module that can help users set and manage timers and reminders directly from the picker. This can include actions for setting timers, creating reminders, and showing upcoming timers and reminders in the picker preview.
- [x] Implement actions for setting timers with specific durations, creating reminders for specific dates and times, and showing a list of upcoming timers and reminders in the picker preview to help users stay organized and on top of their tasks.

### Phase 53: Math/conversion module

- [x] Create a math and conversion module that can perform various mathematical calculations and unit conversions directly from the picker
- [x] Parse query and provide actions for copying results into clipboard
- [x] Implement parsers for arithmetic expressions, currency conversions, unit conversions, and other common calculations to make it easy for users to perform quick calculations without leaving the picker
- [x] Boost actions provided by this module since if query is parsed as math expression or conversion it is very likely that user wants to execute these actions

### Phase 55: Faster picker toggle (DONE)

- [x] Implement a faster picker toggle mechanism that can show the picker more quickly and responsively when the user triggers it with a key-combo
- [x] Retain picker state (query, selected action) when toggling it off and on to allow users to quickly hide and show the picker without losing their place
- [x] Optimize action list loading, maybe introduce caching when query is empty to show at least some actions immediately on picker open and then update them when modules provide results

### Phase 54: Remove redundant actions and Merge similar modules

- [x] Review all existing actions and remove any that are redundant, not useful, or can be easily replaced by other actions. This will help streamline the app and make it easier for users to find and use the most relevant actions.
- [x] Merge some actions, like now playing with cover preview should be add to liked songs
- [x] Review existing modules and merge any that have overlapping functionality or can be logically grouped together
- [x] Merge bookmarks and browser modules
- [x] Move app related code like app theme changing to corresponding app modules or helpers

### Phase 57: Testing (DONE)

- [x] Write checklist file for manual testing of the app, covering all features and edge cases. This will help ensure that the app is stable and works as expected before release.
- [x] Add some XCUI tests for critical user flows like showing the picker, searching for actions, executing actions, and handling permissions to catch any regressions in these areas during development.

### Phase 58: Simplify config

- [x] make all module configuration optional with sane defaults, keep loading modules only if their section is present in config
- [x] unify keybindings and key/mouse remaps in a single config section
- [x] unify action strings in keybindings/aliases: module/action?param=value&param2=value2, handle these actions via vibeshed:// URI scheme internally to reuse the same parsing and execution logic for all actions in the app

### Phase 59: Simplify theme engine (DONE)

- [x] simplify theme engine by removing intensity parameter and just making vibe-based theme changes noticeable by default

### Phase 59: Branding and website (DONE)

- [x] Come up with a kickass name and icon for the app that reflects its functionality and vibe
- [x] Make sure it follows apple UX guidelines and unix principles at least to some extent
- [x] Create a website on github pages for the app with documentation, screenshots, and download links to make it easy for users to learn about the app and get it installed on their systems
- [x] Set propper bundle identifier, versioning and code signing for the app to ensure it can be distributed and installed properly on user systems


### Phase 60: More contrast, readability and accessibility improvements (DONE)

- [x] UI overal more contrasty and readable, but also follow Apple's design principles and guidelines to make sure the app feels native and intuitive to use. This can include using appropriate font sizes, colors, and spacing to create a visually appealing and easy-to-use interface

### Phase 61: Scrolling performance improvements (DONE)

- [x] Optimize the performance of the picker when displaying long lists of actions, for example by implementing lazy loading or pagination to ensure that the app remains responsive and smooth even with a large number of actions available.

### Phase 62: Bugfixing and polishing

- [ ] Based on testing and user feedback, fix any bugs and polish the app's UI and UX to make it as smooth and enjoyable to use as possible. This can include improving animations, optimizing performance, and refining the design.

### Phase 63: Releases and distribution 

- [ ] State project goals and non-goals clearly in the readme to set the right expectations for users and contributors
- [ ] Make sure gitingnore file is configured to not include any sensitive information, build artifacts, or other unnecessary files in the repository
- [ ] Publish the app on github with proper license, readme, and some documentation
- [ ] Set up a release process for the app, including building, signing, and distributing the app through github releases and homebrew
- [ ] Set up github donations for the project to allow users to support development if they find the app useful and want to contribute financially to its ongoing maintenance and improvement
