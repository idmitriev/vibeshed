import Foundation
import OSLog

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.ivandmitriev.Vibeshed"

    /// Mirror warning/error messages to stderr when running from a terminal.
    static let stderrEnabled: Bool = {
        isatty(STDERR_FILENO) != 0 || CommandLine.arguments.contains("--stderr-log")
    }()

    static let app = Logger(subsystem: subsystem, category: "app")
    static let picker = Logger(subsystem: subsystem, category: "picker")
    static let modules = Logger(subsystem: subsystem, category: "modules")
    static let config = Logger(subsystem: subsystem, category: "config")
    static let events = Logger(subsystem: subsystem, category: "events")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
    static let keybindings = Logger(subsystem: subsystem, category: "keybindings")
    static let uri = Logger(subsystem: subsystem, category: "uri")
    static let layout = Logger(subsystem: subsystem, category: "layout")

    static func module(_ name: String) -> Logger {
        Logger(subsystem: subsystem, category: "module.\(name)")
    }

    /// Write a message to stderr so it appears in the launching terminal.
    static func stderr(_ message: String) {
        guard stderrEnabled else { return }
        let timestamp = stderrDateFormatter.string(from: Date())
        FileHandle.standardError.write(Data("[\(timestamp)] \(message)\n".utf8))
    }

    private static let stderrDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt
    }()
}
