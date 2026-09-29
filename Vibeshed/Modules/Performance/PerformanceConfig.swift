import Foundation

struct PerformanceConfig: Codable, Sendable, Equatable {
    /// Seconds between samples. Sampling runs in the background, so the history is
    /// already there when the picker opens.
    var sampleInterval: Double = 2
    /// How far back the preview charts and their averages and peaks reach.
    var historyMinutes: Int = 60
    /// BSD names of the interfaces the network figures count (e.g. `["en0"]`). Unset
    /// counts every active Ethernet, Wi-Fi and cellular interface, leaving out loopback,
    /// VPN tunnels, bridges and VM interfaces, whose traffic also crosses a physical one.
    var networkInterfaces: [String]?
    /// Action names to show (`overview`, `cpu`, `memory`, `disk`, `network`); unset shows all.
    var enabledActions: Set<String>?

    static let sampleIntervalRange: ClosedRange<Double> = 0.5 ... 60
    static let historyMinutesRange: ClosedRange<Int> = 1 ... 1440

    init() {}

    /// Codable synthesis ignores Swift property defaults, so decode each field
    /// leniently — a user's section may specify only some keys.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sampleInterval = try container.decodeIfPresent(Double.self, forKey: .sampleInterval) ?? 2
        historyMinutes = try container.decodeIfPresent(Int.self, forKey: .historyMinutes) ?? 60
        networkInterfaces = try container.decodeIfPresent([String].self, forKey: .networkInterfaces)
        enabledActions = try container.decodeIfPresent(Set<String>.self, forKey: .enabledActions)
    }

    private enum CodingKeys: String, CodingKey {
        case sampleInterval
        case historyMinutes
        case networkInterfaces
        case enabledActions
    }

    var historyWindow: TimeInterval {
        TimeInterval(historyMinutes * 60)
    }
}
