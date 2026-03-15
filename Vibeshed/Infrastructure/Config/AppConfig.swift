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
        var panelWidth: Double = 680
        var panelHeight: Double = 460
        var cornerRadius: Double = 12
    }
}
