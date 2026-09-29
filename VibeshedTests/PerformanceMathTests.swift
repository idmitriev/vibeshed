import Darwin
@testable import Vibeshed
import XCTest

/// Turning kernel counter readings into rates and splits, without the kernel.
final class PerformanceMathTests: XCTestCase {
    // MARK: - CPU

    func testCPUSplitsUserSystemAndIdleAcrossCores() {
        let old = [
            CPUTicks(user: 100, system: 50, idle: 850, nice: 0),
            CPUTicks(user: 0, system: 0, idle: 1000, nice: 0),
        ]
        let new = [
            CPUTicks(user: 160, system: 70, idle: 870, nice: 10),
            CPUTicks(user: 0, system: 0, idle: 1100, nice: 0),
        ]
        // Core 0: 60 user + 10 nice, 20 system, 20 idle. Core 1: 100 idle.
        let reading = PerformanceMath.cpu(from: old, to: new)
        XCTAssertEqual(reading.user, 70.0 / 210, accuracy: 1e-9)
        XCTAssertEqual(reading.system, 20.0 / 210, accuracy: 1e-9)
        XCTAssertEqual(reading.idle, 120.0 / 210, accuracy: 1e-9)
        XCTAssertEqual(reading.cores.count, 2)
        XCTAssertEqual(reading.cores[0], 90.0 / 110, accuracy: 1e-9)
        XCTAssertEqual(reading.cores[1], 0)
    }

    func testCPUTicksWrapAround() {
        let old = [CPUTicks(user: UInt32.max - 9, system: 0, idle: UInt32.max - 9, nice: 0)]
        let new = [CPUTicks(user: 10, system: 0, idle: 10, nice: 0)]
        XCTAssertEqual(PerformanceMath.cpu(from: old, to: new).user, 0.5, accuracy: 1e-9)
    }

    func testCPUWithADifferentCoreCountReadsIdle() {
        let reading = PerformanceMath.cpu(from: [], to: [CPUTicks(user: 5, system: 5, idle: 5, nice: 0)])
        XCTAssertEqual(reading.usage, 0)
        XCTAssertEqual(reading.cores, [0])
    }

    // MARK: - Memory

    func testMemoryFollowsActivityMonitorsSplit() {
        let page: UInt64 = 16384
        var raw = Self.counters(uptime: 1)
        raw.physicalMemory = 100_000 * page
        raw.vm = VMCounts(
            pageSize: page, free: 1000, speculative: 100, wired: 20000,
            compressed: 30000, internalPages: 50000, external: 10000, purgeable: 2000
        )
        let memory = PerformanceMath.memory(raw)
        XCTAssertEqual(memory.cachedFiles, 12000 * page)
        XCTAssertEqual(memory.app, 48000 * page)
        XCTAssertEqual(memory.wired, 20000 * page)
        XCTAssertEqual(memory.compressed, 30000 * page)
        // Everything but free, speculative and cached files — kernel memory included.
        XCTAssertEqual(memory.used, (100_000 - 1000 - 100 - 12000) * page)
        XCTAssertEqual(memory.usedFraction, 0.869, accuracy: 1e-9)
    }

    func testMemoryUsedNeverUnderflows() {
        var raw = Self.counters(uptime: 1)
        raw.physicalMemory = 1000
        raw.vm.free = 10
        XCTAssertEqual(PerformanceMath.memory(raw).used, 0)
    }

    // MARK: - Counters

    func testCounterDeltaHandlesWrapsAndRestarts() {
        XCTAssertEqual(PerformanceMath.counterDelta(from: 100, to: 250), 150)
        // A byte counter truncated to 32 bits passing 4 GiB.
        XCTAssertEqual(PerformanceMath.counterDelta(from: (1 << 32) - 100, to: 50), 150)
        // A counter that started over, e.g. an interface that came back.
        XCTAssertEqual(PerformanceMath.counterDelta(from: 5000, to: 1200), 1200)
        // A drop in a full 64-bit counter is never taken for a 32-bit wrap.
        XCTAssertEqual(PerformanceMath.counterDelta(from: 6_000_000_000, to: 10), 10)
    }

    func testDiskRatesSkipNewDisksButCountThemInTotals() {
        let old: [UInt64: DiskCounters] = [1: DiskCounters(bytesRead: 1000, bytesWritten: 500, reads: 10, writes: 5)]
        let new: [UInt64: DiskCounters] = [
            1: DiskCounters(bytesRead: 5000, bytesWritten: 2500, reads: 30, writes: 15),
            2: DiskCounters(bytesRead: 1_000_000, bytesWritten: 0, reads: 100, writes: 0),
        ]
        let disk = PerformanceMath.disk(from: old, to: new, elapsed: 2)
        XCTAssertEqual(disk.readBytesPerSecond, 2000)
        XCTAssertEqual(disk.writeBytesPerSecond, 1000)
        XCTAssertEqual(disk.readsPerSecond, 10)
        XCTAssertEqual(disk.writesPerSecond, 5)
        XCTAssertEqual(disk.totalRead, 1_005_000)
        XCTAssertEqual(disk.totalWritten, 2500)
    }

    func testNetworkSumsInterfacesBusiestFirst() {
        let old = [
            "en0": InterfaceCounters(bytesIn: 1000, bytesOut: 100, packetsIn: 10, packetsOut: 1),
            "awdl0": InterfaceCounters(bytesIn: 0, bytesOut: 0, packetsIn: 0, packetsOut: 0),
        ]
        let new = [
            "en0": InterfaceCounters(bytesIn: 3000, bytesOut: 300, packetsIn: 30, packetsOut: 3),
            "awdl0": InterfaceCounters(bytesIn: 4000, bytesOut: 0, packetsIn: 20, packetsOut: 0),
            "en7": InterfaceCounters(bytesIn: 9_000_000, bytesOut: 0, packetsIn: 0, packetsOut: 0),
        ]
        let network = PerformanceMath.network(from: old, to: new, elapsed: 2)
        XCTAssertEqual(network.interfaces.map(\.name), ["awdl0", "en0"])
        XCTAssertEqual(network.receivedBytesPerSecond, 3000)
        XCTAssertEqual(network.sentBytesPerSecond, 100)
        XCTAssertEqual(network.receivedPacketsPerSecond, 20)
        XCTAssertEqual(network.sentPacketsPerSecond, 1)
    }

    func testSampleNeedsTimeToPass() {
        let raw = Self.counters(uptime: 10)
        XCTAssertNil(PerformanceMath.sample(from: raw, to: raw, date: Date()))
        let later = Self.counters(uptime: 12.5)
        XCTAssertEqual(PerformanceMath.sample(from: raw, to: later, date: Date())?.interval, 2.5)
    }

    // MARK: - Live

    func testTwoReadingsOfThisMachineMakeASaneSample() throws {
        let first = PerformanceProbe.read(interfaces: .automatic)
        XCTAssertFalse(first.cpu.isEmpty)
        XCTAssertGreaterThan(first.vm.pageSize, 0)
        XCTAssertEqual(first.loadAverage.count, 3)
        Thread.sleep(forTimeInterval: 0.2)
        let second = PerformanceProbe.read(interfaces: .automatic)
        let sample = try XCTUnwrap(PerformanceMath.sample(from: first, to: second, date: Date()))
        XCTAssertEqual(sample.cpu.user + sample.cpu.system + sample.cpu.idle, 1, accuracy: 1e-6)
        XCTAssertEqual(sample.cpu.cores.count, first.cpu.count)
        XCTAssertGreaterThan(sample.memory.used, 0)
        XCTAssertLessThanOrEqual(sample.memory.used, sample.memory.total)
    }

    // MARK: - Interfaces

    func testAutomaticSelectionSkipsInterfacesThatRepeatPhysicalTraffic() {
        let up = IFF_UP | IFF_RUNNING
        let selection = InterfaceSelection.automatic
        XCTAssertTrue(selection.includes(name: "en0", flags: up, type: 0x06))
        XCTAssertTrue(selection.includes(name: "pdp_ip0", flags: up, type: 0xFF))
        XCTAssertFalse(selection.includes(name: "en5", flags: 0, type: 0x06), "down")
        XCTAssertFalse(selection.includes(name: "lo0", flags: up | IFF_LOOPBACK, type: 0x18))
        XCTAssertFalse(selection.includes(name: "utun4", flags: up | IFF_POINTOPOINT, type: 0x01))
        XCTAssertFalse(selection.includes(name: "bridge100", flags: up, type: 0x06))
        XCTAssertFalse(selection.includes(name: "vmenet0", flags: up, type: 0x06))
        XCTAssertFalse(selection.includes(name: "ap1", flags: up, type: 0x06))
    }

    func testNamedSelectionCountsExactlyThoseInterfaces() {
        let selection = InterfaceSelection(names: ["en7"])
        XCTAssertTrue(selection.includes(name: "en7", flags: 0, type: 0))
        XCTAssertFalse(selection.includes(name: "en0", flags: IFF_UP, type: 0x06))
        XCTAssertEqual(InterfaceSelection(names: nil), .automatic)
    }

    // MARK: - Helpers

    private static func counters(uptime: TimeInterval) -> RawCounters {
        RawCounters(
            uptime: uptime,
            cpu: [],
            vm: VMCounts(
                pageSize: 16384, free: 0, speculative: 0, wired: 0,
                compressed: 0, internalPages: 0, external: 0, purgeable: 0
            ),
            physicalMemory: 16 << 30,
            swapUsed: 0,
            swapTotal: 0,
            pressure: .normal,
            loadAverage: [1, 2, 3],
            disks: [:],
            interfaces: [:]
        )
    }
}
