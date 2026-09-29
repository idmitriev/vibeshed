import Foundation

/// A resource the module watches. Each has an action whose preview charts it and
/// which opens Activity Monitor on the matching tab.
enum PerformanceMetric: String, CaseIterable, Sendable {
    case cpu
    case memory
    case disk
    case network

    /// Action title.
    var title: String {
        switch self {
        case .cpu: "CPU Usage"
        case .memory: "RAM & Memory Usage"
        case .disk: "Disk Activity"
        case .network: "Network Activity"
        }
    }

    /// Label in the overview and in charts.
    var shortTitle: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .disk: "Disk"
        case .network: "Network"
        }
    }

    var iconName: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "network"
        }
    }

    var keywords: [String] {
        let shared = ["performance", "usage", "activity monitor", "monitor", "stats", "system"]
        switch self {
        case .cpu:
            return shared + ["cpu", "processor", "load", "cores", "busy", "hot"]
        case .memory:
            return shared + ["memory usage", "ram usage", "memory", "ram", "swap", "pressure", "compressed", "mem"]
        case .disk:
            return shared + ["disk", "io", "read", "write", "storage", "ssd", "drive", "throughput"]
        case .network:
            return shared + ["network", "bandwidth", "download", "upload", "traffic", "internet", "speed", "net"]
        }
    }

    var activityMonitorTab: ActivityMonitor.Tab {
        switch self {
        case .cpu: .cpu
        case .memory: .memory
        case .disk: .disk
        case .network: .network
        }
    }
}
