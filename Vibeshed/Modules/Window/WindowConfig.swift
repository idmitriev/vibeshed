import Foundation

struct WindowConfig: Codable, Sendable, Equatable {
    var horizontalStops: [SizeStop]
    var verticalStops: [SizeStop]
    var padding: PaddingConfig
    var includeMinimized: Bool
    var enlargeShrinkStep: SizeStop

    static let defaultValue = WindowConfig(
        horizontalStops: [
            SizeStop(value: 50, unit: .percent),
            SizeStop(value: 33.33, unit: .percent),
            SizeStop(value: 66.67, unit: .percent),
            SizeStop(value: 100, unit: .percent),
        ],
        verticalStops: [
            SizeStop(value: 50, unit: .percent),
            SizeStop(value: 100, unit: .percent),
        ],
        padding: PaddingConfig(),
        includeMinimized: false,
        enlargeShrinkStep: SizeStop(value: 10, unit: .percent)
    )
}

struct SizeStop: Codable, Sendable, Equatable {
    let value: Double
    let unit: SizeUnit
}

enum SizeUnit: String, Codable, Sendable, Equatable {
    case percent
    case pixels
}

struct PaddingConfig: Codable, Sendable, Equatable {
    var top: Double = 0
    var bottom: Double = 0
    var left: Double = 0
    var right: Double = 0
    var gap: Double = 0
}
