import Foundation

struct AppConfig: Codable, Sendable, Equatable {
    var hotkey: HotkeyConfig = .init()
    var appearance: AppearanceConfig = .init()
    var modules: [ModuleConfig] = []

    struct HotkeyConfig: Codable, Sendable, Equatable {
        var key: String = "space"
        var modifiers: [String] = ["option"]
    }

    struct AppearanceConfig: Codable, Sendable, Equatable {
        var panelWidth: Double = 680
        var panelHeight: Double = 460
        var cornerRadius: Double = 12
    }

    struct ModuleConfig: Codable, Sendable, Equatable, Identifiable {
        var id: String { name }
        var name: String
        var enabled: Bool = true
        var settings: [String: String] = [:]
    }
}
