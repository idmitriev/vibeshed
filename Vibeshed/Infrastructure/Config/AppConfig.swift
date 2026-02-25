import Foundation

struct AppConfig: Sendable, Equatable {
    var appearance: AppearanceConfig = .init()
    var keybindings: [KeyBindingEntry] = []
    var keyRemaps: [KeyRemapGroup] = []
    var mouseRemaps: [MouseRemapEntry] = []
    var moduleConfigs: [String: Data] = [:]
    var urlRouting: URLRoutingConfig = .init()
    var aliases: [AliasEntry] = []

    struct AppearanceConfig: Codable, Sendable, Equatable {
        var panelWidth: Double = 680
        var panelHeight: Double = 460
        var cornerRadius: Double = 12
        var themeIntensity: Double = 0
    }
}
