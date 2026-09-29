import Foundation

/// Busy time over the last interval, as fractions (0…1) of all cores' time.
struct CPUReading: Sendable, Equatable {
    /// User time, including niced processes.
    var user: Double
    var system: Double
    var idle: Double
    /// Busy fraction of each logical core, in core order.
    var cores: [Double]

    var usage: Double {
        min(1, user + system)
    }
}

/// `kern.memorystatus_vm_pressure_level`, the level Activity Monitor's pressure graph shows.
enum MemoryPressure: Int, Sendable, Comparable {
    case normal = 1
    case warning = 2
    case critical = 4

    init(level: Int32) {
        self = level >= 4 ? .critical : level >= 2 ? .warning : .normal
    }

    var label: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }

    static func < (lhs: MemoryPressure, rhs: MemoryPressure) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Memory in bytes, split the way Activity Monitor's Memory tab splits it.
struct MemoryReading: Sendable, Equatable {
    var total: UInt64
    /// Everything but free memory and cached files: what apps can't get back without
    /// compressing or swapping.
    var used: UInt64
    var app: UInt64
    var wired: UInt64
    /// Physical memory the compressor holds.
    var compressed: UInt64
    /// File-backed and purgeable memory the system can reclaim at any time.
    var cachedFiles: UInt64
    var swapUsed: UInt64
    var swapTotal: UInt64
    var pressure: MemoryPressure

    var usedFraction: Double {
        total > 0 ? Double(used) / Double(total) : 0
    }
}

struct DiskReading: Sendable, Equatable {
    var readBytesPerSecond: Double
    var writeBytesPerSecond: Double
    var readsPerSecond: Double
    var writesPerSecond: Double
    /// Since boot, summed over every disk.
    var totalRead: UInt64
    var totalWritten: UInt64

    var bytesPerSecond: Double {
        readBytesPerSecond + writeBytesPerSecond
    }
}

struct InterfaceReading: Sendable, Equatable, Identifiable {
    /// BSD name, e.g. `en0`.
    var name: String
    var receivedBytesPerSecond: Double
    var sentBytesPerSecond: Double

    var id: String {
        name
    }

    var bytesPerSecond: Double {
        receivedBytesPerSecond + sentBytesPerSecond
    }
}

struct NetworkReading: Sendable, Equatable {
    var receivedBytesPerSecond: Double
    var sentBytesPerSecond: Double
    var receivedPacketsPerSecond: Double
    var sentPacketsPerSecond: Double
    /// Counted interfaces, busiest first.
    var interfaces: [InterfaceReading]

    var bytesPerSecond: Double {
        receivedBytesPerSecond + sentBytesPerSecond
    }
}

/// Everything one sampling tick measured.
struct PerformanceSample: Sendable, Equatable {
    var date: Date
    /// Seconds of uptime the rates were measured over.
    var interval: TimeInterval
    var cpu: CPUReading
    var memory: MemoryReading
    var disk: DiskReading
    var network: NetworkReading
    /// 1, 5 and 15 minute load averages.
    var loadAverage: [Double]
}
