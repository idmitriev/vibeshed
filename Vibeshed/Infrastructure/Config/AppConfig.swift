import Foundation

struct AppConfig: Sendable, Equatable {
    var appearance: AppearanceConfig = .init()
    var keybindings: [KeyBindingEntry] = []
    /// Bundle IDs where every keybinding and remap is suppressed — the event
    /// tap passes input straight through while one of these apps is focused.
    /// Matched case-insensitively.
    var keybindingExclusions: [String] = []
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
        /// Backdrop behind the open picker; nil when the section is absent.
        var overlay: OverlayConfig?
    }
}

extension AppConfig.AppearanceConfig {
    /// The overlay to draw, if it's configured and not switched off.
    var activeOverlay: AppConfig.OverlayConfig? {
        overlay.flatMap { $0.enabled ? $0 : nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        panelWidth = try container.decodeIfPresent(Double.self, forKey: .panelWidth) ?? defaults.panelWidth
        panelHeight = try container.decodeIfPresent(Double.self, forKey: .panelHeight) ?? defaults.panelHeight
        cornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? defaults.cornerRadius
        rowHeight = try container.decodeIfPresent(Double.self, forKey: .rowHeight) ?? defaults.rowHeight
        searchBarHeight = try container.decodeIfPresent(Double.self, forKey: .searchBarHeight)
            ?? defaults.searchBarHeight
        overlay = Self.decodeOverlay(from: container)
    }

    /// `overlay:` with no value (or `true`) turns it on with defaults, `false` off. A
    /// value that isn't a mapping is logged and falls back to the defaults rather than
    /// taking the panel settings above down with it.
    private static func decodeOverlay(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> AppConfig.OverlayConfig? {
        guard container.contains(.overlay) else { return nil }
        if (try? container.decodeNil(forKey: .overlay)) == true {
            return AppConfig.OverlayConfig()
        }
        if let flag = try? container.decode(Bool.self, forKey: .overlay) {
            return flag ? AppConfig.OverlayConfig() : nil
        }
        do {
            return try container.decode(AppConfig.OverlayConfig.self, forKey: .overlay)
        } catch {
            let message = "Ignoring invalid 'appearance.overlay', using defaults: \(error.localizedDescription)"
            Log.config.error("\(message, privacy: .public)")
            return AppConfig.OverlayConfig()
        }
    }
}
