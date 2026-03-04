import Foundation

struct TimerConfig: Codable, Sendable, Equatable {
    var defaultSound: String = "Glass"
    var presetDurations: [Int] = [1, 5, 10, 15, 30, 60]
    var maxActiveTimers: Int = 20
    var enabledActions: Set<String>?
}
