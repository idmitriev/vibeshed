import Darwin
import Foundation
import IOKit

/// Which interfaces the network figures count.
enum InterfaceSelection: Sendable, Equatable {
    /// Every active Ethernet, Wi-Fi or cellular interface except the ones whose traffic
    /// also crosses a physical interface: loopback, point-to-point VPN tunnels, bridges,
    /// VM and Internet Sharing interfaces.
    case automatic
    case named(Set<String>)

    init(names: [String]?) {
        self = names.map { .named(Set($0)) } ?? .automatic
    }

    private static let ethernetType: UInt8 = 0x06 // IFT_ETHER, which Wi-Fi reports too
    private static let cellularType: UInt8 = 0xFF // IFT_CELLULAR
    private static let derivedPrefixes = ["bridge", "vmenet", "ap"]

    func includes(name: String, flags: Int32, type: UInt8) -> Bool {
        switch self {
        case let .named(names):
            return names.contains(name)
        case .automatic:
            guard flags & IFF_UP != 0,
                  flags & (IFF_LOOPBACK | IFF_POINTOPOINT) == 0,
                  type == Self.ethernetType || type == Self.cellularType
            else {
                return false
            }
            return !Self.derivedPrefixes.contains { name.hasPrefix($0) }
        }
    }
}

/// Reads the kernel counters the module samples. Each read takes well under a
/// millisecond and is safe from any thread.
enum PerformanceProbe {
    static func read(interfaces selection: InterfaceSelection) -> RawCounters {
        let swap = swapUsage()
        return RawCounters(
            uptime: ProcessInfo.processInfo.systemUptime,
            cpu: cpuTicks(),
            vm: vmCounts(),
            physicalMemory: ProcessInfo.processInfo.physicalMemory,
            swapUsed: swap.used,
            swapTotal: swap.total,
            pressure: MemoryPressure(level: sysctlInt32("kern.memorystatus_vm_pressure_level") ?? 1),
            loadAverage: loadAverage(),
            disks: diskCounters(),
            interfaces: interfaceCounters(selection)
        )
    }

    // MARK: - CPU

    static func cpuTicks() -> [CPUTicks] {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return [] }
        defer {
            let size = vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), size)
        }
        let stride = Int(CPU_STATE_MAX)
        return (0 ..< Int(cpuCount)).map { cpu in
            let base = cpu * stride
            return CPUTicks(
                user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            )
        }
    }

    static func loadAverage() -> [Double] {
        var loads = [Double](repeating: 0, count: 3)
        return getloadavg(&loads, 3) == 3 ? loads : []
    }

    // MARK: - Memory

    static func vmCounts() -> VMCounts {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        guard result == KERN_SUCCESS else {
            return VMCounts(
                pageSize: UInt64(pageSize), free: 0, speculative: 0, wired: 0,
                compressed: 0, internalPages: 0, external: 0, purgeable: 0
            )
        }
        return VMCounts(
            pageSize: UInt64(pageSize),
            free: UInt64(stats.free_count),
            speculative: UInt64(stats.speculative_count),
            wired: UInt64(stats.wire_count),
            compressed: UInt64(stats.compressor_page_count),
            internalPages: UInt64(stats.internal_page_count),
            external: UInt64(stats.external_page_count),
            purgeable: UInt64(stats.purgeable_count)
        )
    }

    private static func swapUsage() -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return (0, 0) }
        return (usage.xsu_used, usage.xsu_total)
    }

    // MARK: - Disk

    /// Per-disk I/O statistics from IOKit — the counters Activity Monitor's Disk tab sums.
    static func diskCounters() -> [UInt64: DiskCounters] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator
        ) == KERN_SUCCESS else {
            return [:]
        }
        defer { IOObjectRelease(iterator) }

        var disks: [UInt64: DiskCounters] = [:]
        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }
            var entryID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS,
                  let property = IORegistryEntryCreateCFProperty(
                      service, "Statistics" as CFString, kCFAllocatorDefault, 0
                  )?.takeRetainedValue(),
                  let statistics = property as? [String: Any]
            else {
                continue
            }
            func counter(_ key: String) -> UInt64 {
                (statistics[key] as? NSNumber)?.uint64Value ?? 0
            }
            disks[entryID] = DiskCounters(
                bytesRead: counter("Bytes (Read)"),
                bytesWritten: counter("Bytes (Write)"),
                reads: counter("Operations (Read)"),
                writes: counter("Operations (Write)")
            )
        }
        return disks
    }

    // MARK: - Network

    /// Interface counters from the routing socket's `NET_RT_IFLIST2` table.
    static func interfaceCounters(_ selection: InterfaceSelection) -> [String: InterfaceCounters] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return [:] }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else { return [:] }

        var interfaces: [String: InterfaceCounters] = [:]
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                defer { offset += Int(header.ifm_msglen) }
                guard Int32(header.ifm_type) == RTM_IFINFO2,
                      offset + MemoryLayout<if_msghdr2>.size <= length
                else {
                    continue
                }
                let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                let linkAddress = offset + MemoryLayout<if_msghdr2>.size
                let end = min(length, offset + Int(header.ifm_msglen))
                guard let name = linkName(in: raw, at: linkAddress, end: end, addresses: message.ifm_addrs)
                    ?? interfaceName(index: message.ifm_index),
                    selection.includes(name: name, flags: message.ifm_flags, type: message.ifm_data.ifi_type)
                else {
                    continue
                }
                let data = message.ifm_data
                interfaces[name] = InterfaceCounters(
                    bytesIn: data.ifi_ibytes,
                    bytesOut: data.ifi_obytes,
                    packetsIn: data.ifi_ipackets,
                    packetsOut: data.ifi_opackets
                )
            }
        }
        return interfaces
    }

    /// The interface's name from the link-level address (`sockaddr_dl`) right after an
    /// `RTM_IFINFO2` header, where `netstat` reads it; `if_indextoname` would cost a
    /// system call per interface.
    private static func linkName(in raw: UnsafeRawBufferPointer, at start: Int, end: Int, addresses: Int32) -> String? {
        // sockaddr_dl: length, family, index (2 bytes), type, name length, address
        // length, selector length, then the name.
        guard addresses & RTA_IFP != 0, start + 8 <= end, raw[start + 1] == UInt8(AF_LINK) else { return nil }
        let nameStart = start + 8
        let nameEnd = nameStart + Int(raw[start + 5])
        guard nameEnd > nameStart, nameEnd <= end else { return nil }
        return String(bytes: raw[nameStart ..< nameEnd], encoding: .utf8)
    }

    private static func interfaceName(index: UInt16) -> String? {
        var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        guard if_indextoname(UInt32(index), &name) != nil else { return nil }
        return string(fromCString: name)
    }

    /// The UTF-8 text in a NUL-terminated C buffer.
    static func string(fromCString buffer: [CChar]) -> String? {
        String(bytes: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8)
    }

    // MARK: - sysctl

    static func sysctlInt32(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return string(fromCString: buffer)
    }
}
