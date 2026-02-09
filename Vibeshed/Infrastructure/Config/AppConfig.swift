import Foundation

struct AppConfig: Sendable, Equatable {
    var hotkey: HotkeyConfig = .init()
    var appearance: AppearanceConfig = .init()
    var moduleConfigs: [String: Data] = [:]

    struct HotkeyConfig: Codable, Sendable, Equatable {
        var key: String = "space"
        var modifiers: [String] = ["option"]
    }

    struct AppearanceConfig: Codable, Sendable, Equatable {
        var panelWidth: Double = 680
        var panelHeight: Double = 460
        var cornerRadius: Double = 12
    }
}
