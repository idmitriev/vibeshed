import Foundation

struct AppConfig: Sendable, Equatable {
    var appearance: AppearanceConfig = .init()
    var keybindings: [KeyBindingEntry] = []
    var moduleConfigs: [String: Data] = [:]
    var urlRouting: URLRoutingConfig = .init()
    var aliases: [AliasEntry] = []
    var layoutCorrection: LayoutCorrectionConfig = .init()

    struct LayoutCorrectionConfig: Codable, Sendable, Equatable {
        var enabled: Bool = true
    }

    struct AppearanceConfig: Codable, Sendable, Equatable {
        var panelWidth: Double = 760
        // Default fits exactly 8 list rows: 56 (search bar) + 8 × 52 (row).
        var panelHeight: Double = 472
        var cornerRadius: Double = 12
        var rowHeight: Double = 52
        var searchBarHeight: Double = 56
    }
}
