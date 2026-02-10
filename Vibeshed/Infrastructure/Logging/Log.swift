import OSLog

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.vibeshed"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let picker = Logger(subsystem: subsystem, category: "picker")
    static let modules = Logger(subsystem: subsystem, category: "modules")
    static let config = Logger(subsystem: subsystem, category: "config")
    static let events = Logger(subsystem: subsystem, category: "events")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
    static let keybindings = Logger(subsystem: subsystem, category: "keybindings")
    static let uri = Logger(subsystem: subsystem, category: "uri")

    static func module(_ name: String) -> Logger {
        Logger(subsystem: subsystem, category: "module.\(name)")
    }
}
