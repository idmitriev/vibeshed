import Foundation

/// Cumulative ticks of one logical core, from `host_processor_info`.
struct CPUTicks: Sendable, Equatable {
    var user: UInt32
    var system: UInt32
    var idle: UInt32
    var nice: UInt32
}

/// Page counts from `host_statistics64(HOST_VM_INFO64)`.
struct VMCounts: Sendable, Equatable {
    var pageSize: UInt64
    var free: UInt64
    var speculative: UInt64
    var wired: UInt64
    /// Pages the compressor occupies.
    var compressed: UInt64
    /// Anonymous (app) pages.
    var internalPages: UInt64
    /// File-backed pages.
    var external: UInt64
    var purgeable: UInt64
}

struct DiskCounters: Sendable, Equatable {
    var bytesRead: UInt64
    var bytesWritten: UInt64
    var reads: UInt64
    var writes: UInt64
}

struct InterfaceCounters: Sendable, Equatable {
    var bytesIn: UInt64
    var bytesOut: UInt64
    var packetsIn: UInt64
    var packetsOut: UInt64
}

/// One reading of the kernel's counters. Rates come from two consecutive readings.
struct RawCounters: Sendable, Equatable {
    /// Seconds since boot, not counting sleep (the counters don't move during sleep either).
    var uptime: TimeInterval
    var cpu: [CPUTicks]
    var vm: VMCounts
    var physicalMemory: UInt64
    var swapUsed: UInt64
    var swapTotal: UInt64
    var pressure: MemoryPressure
    var loadAverage: [Double]
    /// Keyed by IORegistry entry ID, so a disk that comes and goes can't skew the others.
    var disks: [UInt64: DiskCounters]
    /// The interfaces the network figures count, keyed by BSD name.
    var interfaces: [String: InterfaceCounters]
}

/// Turns two counter readings into a sample. Pure, so the arithmetic is testable
/// without the kernel.
enum PerformanceMath {
    static func sample(from old: RawCounters, to new: RawCounters, date: Date) -> PerformanceSample? {
        let elapsed = new.uptime - old.uptime
        guard elapsed > 0 else { return nil }
        return PerformanceSample(
            date: date,
            interval: elapsed,
            cpu: cpu(from: old.cpu, to: new.cpu),
            memory: memory(new),
            disk: disk(from: old.disks, to: new.disks, elapsed: elapsed),
            network: network(from: old.interfaces, to: new.interfaces, elapsed: elapsed),
            loadAverage: new.loadAverage
        )
    }

    static func cpu(from old: [CPUTicks], to new: [CPUTicks]) -> CPUReading {
        guard old.count == new.count else {
            return CPUReading(user: 0, system: 0, idle: 1, cores: Array(repeating: 0, count: new.count))
        }
        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        var cores: [Double] = []
        cores.reserveCapacity(new.count)
        for (before, after) in zip(old, new) {
            // Tick counters are 32-bit and wrap, so subtract with wrapping.
            let coreUser = UInt64(after.user &- before.user) + UInt64(after.nice &- before.nice)
            let coreSystem = UInt64(after.system &- before.system)
            let coreIdle = UInt64(after.idle &- before.idle)
            let coreTotal = coreUser + coreSystem + coreIdle
            cores.append(coreTotal > 0 ? Double(coreUser + coreSystem) / Double(coreTotal) : 0)
            user += coreUser
            system += coreSystem
            idle += coreIdle
        }
        let total = Double(user + system + idle)
        guard total > 0 else {
            return CPUReading(user: 0, system: 0, idle: 1, cores: cores)
        }
        return CPUReading(
            user: Double(user) / total,
            system: Double(system) / total,
            idle: Double(idle) / total,
            cores: cores
        )
    }

    /// Activity Monitor's split: "used" is everything but free memory and cached files,
    /// so it includes kernel memory the page counts don't itemize.
    static func memory(_ counters: RawCounters) -> MemoryReading {
        let vm = counters.vm
        let page = vm.pageSize
        let total = counters.physicalMemory
        let cachedFiles = (vm.external + vm.purgeable) * page
        let available = min(total, (vm.free + vm.speculative) * page + cachedFiles)
        return MemoryReading(
            total: total,
            used: total - available,
            app: vm.internalPages > vm.purgeable ? (vm.internalPages - vm.purgeable) * page : 0,
            wired: vm.wired * page,
            compressed: vm.compressed * page,
            cachedFiles: cachedFiles,
            swapUsed: counters.swapUsed,
            swapTotal: counters.swapTotal,
            pressure: counters.pressure
        )
    }

    static func disk(
        from old: [UInt64: DiskCounters],
        to new: [UInt64: DiskCounters],
        elapsed: TimeInterval
    ) -> DiskReading {
        var bytesRead: UInt64 = 0
        var bytesWritten: UInt64 = 0
        var reads: UInt64 = 0
        var writes: UInt64 = 0
        // A disk that just appeared has no baseline yet; its first interval is skipped.
        for (id, after) in new {
            guard let before = old[id] else { continue }
            bytesRead += counterDelta(from: before.bytesRead, to: after.bytesRead)
            bytesWritten += counterDelta(from: before.bytesWritten, to: after.bytesWritten)
            reads += counterDelta(from: before.reads, to: after.reads)
            writes += counterDelta(from: before.writes, to: after.writes)
        }
        return DiskReading(
            readBytesPerSecond: Double(bytesRead) / elapsed,
            writeBytesPerSecond: Double(bytesWritten) / elapsed,
            readsPerSecond: Double(reads) / elapsed,
            writesPerSecond: Double(writes) / elapsed,
            totalRead: new.values.reduce(0) { $0 + $1.bytesRead },
            totalWritten: new.values.reduce(0) { $0 + $1.bytesWritten }
        )
    }

    static func network(
        from old: [String: InterfaceCounters],
        to new: [String: InterfaceCounters],
        elapsed: TimeInterval
    ) -> NetworkReading {
        var interfaces: [InterfaceReading] = []
        var packetsIn: UInt64 = 0
        var packetsOut: UInt64 = 0
        for (name, after) in new {
            guard let before = old[name] else { continue }
            interfaces.append(InterfaceReading(
                name: name,
                receivedBytesPerSecond: Double(counterDelta(from: before.bytesIn, to: after.bytesIn)) / elapsed,
                sentBytesPerSecond: Double(counterDelta(from: before.bytesOut, to: after.bytesOut)) / elapsed
            ))
            packetsIn += counterDelta(from: before.packetsIn, to: after.packetsIn)
            packetsOut += counterDelta(from: before.packetsOut, to: after.packetsOut)
        }
        interfaces.sort { ($0.bytesPerSecond, $1.name) > ($1.bytesPerSecond, $0.name) }
        return NetworkReading(
            receivedBytesPerSecond: interfaces.reduce(0) { $0 + $1.receivedBytesPerSecond },
            sentBytesPerSecond: interfaces.reduce(0) { $0 + $1.sentBytesPerSecond },
            receivedPacketsPerSecond: Double(packetsIn) / elapsed,
            sentPacketsPerSecond: Double(packetsOut) / elapsed,
            interfaces: interfaces
        )
    }

    /// Growth of a cumulative counter between two readings. Interface counters reach
    /// processes without Apple's network-statistics entitlement truncated to 32 bits, so
    /// a drop of more than half that range is a wrap. Any other drop means the counter
    /// started over, and everything since then is new.
    static func counterDelta(from old: UInt64, to new: UInt64) -> UInt64 {
        if new >= old { return new - old }
        let range: UInt64 = 1 << 32
        if old < range, old - new > range / 2 {
            return range - old + new
        }
        return new
    }
}
