import Foundation

struct AudioConfig: Codable, Sendable, Equatable {
    var volumeSteps: [Int] = [20, 50, 80]
    var volumeStep: Int = 10
    var enabledActions: Set<String>?
}
