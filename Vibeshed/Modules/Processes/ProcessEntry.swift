import Foundation

struct ProcessEntry: Sendable, Equatable {
    let pid: Int32
    let name: String
    let cpuPercent: Double
    let memPercent: Double
    let ports: [Int]
    let bundleURL: URL?
}
