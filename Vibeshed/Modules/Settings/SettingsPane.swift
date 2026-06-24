import Foundation

/// A single macOS System Settings pane that can be opened via the
/// `x-apple.systempreferences:` URL scheme.
struct SettingsPane: Sendable, Equatable {
    /// Stable identifier used in the action name (`settings/<id>`).
    let id: String
    /// Human-readable pane title.
    let title: String
    /// SF Symbol name for the list/preview icon.
    let iconName: String
    /// The pane identifier appended to `x-apple.systempreferences:`.
    /// May include an `?anchor` suffix for sub-sections.
    let target: String
    /// Extra search keywords beyond the title words.
    let keywords: [String]

    /// The full URL string used to open the pane.
    var urlString: String {
        "x-apple.systempreferences:\(target)"
    }
}

extension SettingsPane {
    /// Catalog of common System Settings panes (macOS Ventura+ identifiers).
    static let catalog: [SettingsPane] = [
        // Connectivity
        SettingsPane(
            id: "wifi",
            title: "Wi-Fi",
            iconName: "wifi",
            target: "com.apple.wifi-settings-extension",
            keywords: ["network", "wireless", "internet"]
        ),
        SettingsPane(
            id: "bluetooth",
            title: "Bluetooth",
            iconName: "antenna.radiowaves.left.and.right",
            target: "com.apple.BluetoothSettings",
            keywords: ["wireless", "devices", "pairing"]
        ),
        SettingsPane(
            id: "network",
            title: "Network",
            iconName: "network",
            target: "com.apple.Network-Settings.extension",
            keywords: ["wifi", "ethernet", "vpn", "internet", "proxy"]
        ),

        // System
        SettingsPane(
            id: "general",
            title: "General",
            iconName: "gearshape",
            target: "com.apple.systempreferences.GeneralSettings",
            keywords: ["about", "system"]
        ),
        SettingsPane(
            id: "softwareUpdate",
            title: "Software Update",
            iconName: "arrow.down.circle",
            target: "com.apple.Software-Update-Settings.extension",
            keywords: ["update", "upgrade", "macos", "install"]
        ),
        SettingsPane(
            id: "storage",
            title: "Storage",
            iconName: "internaldrive",
            target: "com.apple.settings.Storage",
            keywords: ["disk", "space", "manage"]
        ),
        SettingsPane(
            id: "dateTime",
            title: "Date & Time",
            iconName: "clock",
            target: "com.apple.Date-Time-Settings.extension",
            keywords: ["clock", "timezone", "time zone"]
        ),
        SettingsPane(
            id: "timeMachine",
            title: "Time Machine",
            iconName: "clock.arrow.circlepath",
            target: "com.apple.Time-Machine-Settings.extension",
            keywords: ["backup", "restore"]
        ),
        SettingsPane(
            id: "sharing",
            title: "Sharing",
            iconName: "square.and.arrow.up",
            target: "com.apple.Sharing-Settings.extension",
            keywords: ["airdrop", "screen sharing", "file sharing"]
        ),

        // Appearance & Desktop
        SettingsPane(
            id: "appearance",
            title: "Appearance",
            iconName: "paintpalette",
            target: "com.apple.Appearance-Settings.extension",
            keywords: ["dark mode", "light mode", "accent", "theme"]
        ),
        SettingsPane(
            id: "desktopDock",
            title: "Desktop & Dock",
            iconName: "dock.rectangle",
            target: "com.apple.Desktop-Settings.extension",
            keywords: ["dock", "mission control", "stage manager", "hot corners"]
        ),
        SettingsPane(
            id: "wallpaper",
            title: "Wallpaper",
            iconName: "photo",
            target: "com.apple.Wallpaper-Settings.extension",
            keywords: ["background", "desktop picture"]
        ),
        SettingsPane(
            id: "screenSaver",
            title: "Screen Saver",
            iconName: "display",
            target: "com.apple.ScreenSaver-Settings.extension",
            keywords: ["saver", "screensaver"]
        ),
        SettingsPane(
            id: "displays",
            title: "Displays",
            iconName: "display.2",
            target: "com.apple.Displays-Settings.extension",
            keywords: ["monitor", "resolution", "brightness", "night shift"]
        ),

        // Control & Notifications
        SettingsPane(
            id: "controlCenter",
            title: "Control Center",
            iconName: "switch.2",
            target: "com.apple.ControlCenter-Settings.extension",
            keywords: ["menu bar", "modules"]
        ),
        SettingsPane(
            id: "notifications",
            title: "Notifications",
            iconName: "bell.badge",
            target: "com.apple.Notifications-Settings.extension",
            keywords: ["alerts", "banners"]
        ),
        SettingsPane(
            id: "sound",
            title: "Sound",
            iconName: "speaker.wave.2",
            target: "com.apple.Sound-Settings.extension",
            keywords: ["audio", "volume", "output", "input", "alert"]
        ),
        SettingsPane(
            id: "focus",
            title: "Focus",
            iconName: "moon",
            target: "com.apple.Focus-Settings.extension",
            keywords: ["do not disturb", "dnd"]
        ),
        SettingsPane(
            id: "screenTime",
            title: "Screen Time",
            iconName: "hourglass",
            target: "com.apple.Screen-Time-Settings.extension",
            keywords: ["limits", "downtime", "usage"]
        ),
        SettingsPane(
            id: "siri",
            title: "Siri & Spotlight",
            iconName: "mic",
            target: "com.apple.Siri-Settings.extension",
            keywords: ["spotlight", "voice", "assistant"]
        ),

        // Privacy & Accounts
        SettingsPane(
            id: "privacy",
            title: "Privacy & Security",
            iconName: "hand.raised",
            target: "com.apple.settings.PrivacySecurity.extension",
            keywords: ["security", "permissions", "firewall", "filevault"]
        ),
        SettingsPane(
            id: "accessibility",
            title: "Accessibility",
            iconName: "figure.wave",
            target: "com.apple.Accessibility-Settings.extension",
            keywords: ["voiceover", "zoom", "display", "a11y"]
        ),
        SettingsPane(
            id: "touchID",
            title: "Touch ID & Password",
            iconName: "touchid",
            target: "com.apple.Touch-ID-Settings.extension",
            keywords: ["fingerprint", "password", "login"]
        ),
        SettingsPane(
            id: "users",
            title: "Users & Groups",
            iconName: "person.2",
            target: "com.apple.Users-Groups-Settings.extension",
            keywords: ["accounts", "login", "guest"]
        ),
        SettingsPane(
            id: "passwords",
            title: "Passwords",
            iconName: "key",
            target: "com.apple.Passwords-Settings.extension",
            keywords: ["keychain", "credentials", "logins"]
        ),
        SettingsPane(
            id: "internetAccounts",
            title: "Internet Accounts",
            iconName: "at",
            target: "com.apple.Internet-Accounts-Settings.extension",
            keywords: ["email", "icloud", "google", "calendar"]
        ),

        // Hardware & Input
        SettingsPane(
            id: "keyboard",
            title: "Keyboard",
            iconName: "keyboard",
            target: "com.apple.Keyboard-Settings.extension",
            keywords: ["shortcuts", "input", "text", "modifier"]
        ),
        SettingsPane(
            id: "trackpad",
            title: "Trackpad",
            iconName: "rectangle.and.hand.point.up.left",
            target: "com.apple.Trackpad-Settings.extension",
            keywords: ["gestures", "tap", "scroll"]
        ),
        SettingsPane(
            id: "mouse",
            title: "Mouse",
            iconName: "computermouse",
            target: "com.apple.Mouse-Settings.extension",
            keywords: ["pointer", "scroll", "tracking"]
        ),
        SettingsPane(
            id: "printers",
            title: "Printers & Scanners",
            iconName: "printer",
            target: "com.apple.Print-Scan-Settings.extension",
            keywords: ["print", "scan"]
        ),
        SettingsPane(
            id: "battery",
            title: "Battery",
            iconName: "battery.100",
            target: "com.apple.Battery-Settings.extension",
            keywords: ["power", "energy", "low power mode"]
        ),
    ]
}
