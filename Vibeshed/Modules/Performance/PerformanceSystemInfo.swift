import Darwin
import Foundation
import IOKit
import SystemConfiguration

enum CoreKind: Sendable, Equatable {
    case performance
    case efficiency
}

/// What the machine is, read once at startup.
struct HardwareInfo: Sendable, Equatable {
    var cpuName: String
    /// Kind of each logical core, in core order; empty when the device tree doesn't say
    /// (Intel Macs).
    var coreKinds: [CoreKind]
    var physicalMemory: UInt64
    var bootDate: Date?

    static func current() -> HardwareInfo {
        HardwareInfo(
            cpuName: PerformanceProbe.sysctlString("machdep.cpu.brand_string") ?? "CPU",
            coreKinds: coreKinds(),
            physicalMemory: ProcessInfo.processInfo.physicalMemory,
            bootDate: bootDate()
        )
    }

    /// "8 cores (6P + 2E)".
    func coreSummary(coreCount: Int) -> String {
        let performance = coreKinds.count { $0 == .performance }
        let efficiency = coreKinds.count { $0 == .efficiency }
        guard coreKinds.count == coreCount, performance > 0, efficiency > 0 else {
            return "\(coreCount) cores"
        }
        return "\(coreCount) cores (\(performance)P + \(efficiency)E)"
    }

    /// Apple silicon lists each core under `IODeviceTree:/cpus` with its logical ID and
    /// cluster type ("E" or "P").
    private static func coreKinds() -> [CoreKind] {
        let cpus = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        guard cpus != IO_OBJECT_NULL else { return [] }
        defer { IOObjectRelease(cpus) }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(cpus, "IODeviceTree", &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var kinds: [Int: CoreKind] = [:]
        while case let cpu = IOIteratorNext(iterator), cpu != IO_OBJECT_NULL {
            defer { IOObjectRelease(cpu) }
            guard let id = integerProperty(cpu, "logical-cpu-id"),
                  let type = stringProperty(cpu, "cluster-type")
            else {
                continue
            }
            kinds[id] = type == "E" ? .efficiency : .performance
        }
        guard !kinds.isEmpty, kinds.keys.sorted() == Array(0 ..< kinds.count) else { return [] }
        return (0 ..< kinds.count).compactMap { kinds[$0] }
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func integerProperty(_ entry: io_registry_entry_t, _ key: String) -> Int? {
        switch property(entry, key) {
        case let number as NSNumber:
            number.intValue
        case let data as Data where data.count >= 4:
            Int(data.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        default:
            nil
        }
    }

    private static func stringProperty(_ entry: io_registry_entry_t, _ key: String) -> String? {
        switch property(entry, key) {
        case let string as String:
            string
        case let data as Data:
            String(bytes: data.prefix { $0 != 0 }, encoding: .utf8)
        default:
            nil
        }
    }

    private static func bootDate() -> Date? {
        var time = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &time, &size, nil, 0) == 0, time.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_usec) / 1_000_000)
    }
}

/// Space on a mounted volume.
struct VolumeUsage: Sendable, Equatable, Identifiable {
    var name: String
    var path: String
    var total: UInt64
    /// Includes purgeable space, as Finder counts it.
    var available: UInt64

    var id: String {
        path
    }

    var used: UInt64 {
        total > available ? total - available : 0
    }

    var usedFraction: Double {
        total > 0 ? Double(used) / Double(total) : 0
    }

    /// The startup volume first, then other local volumes by name.
    static func mounted(limit: Int = 3) -> [VolumeUsage] {
        let keys: [URLResourceKey] = [
            .volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsLocalKey, .volumeIsRootFileSystemKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]
        ) ?? []
        let volumes: [(volume: VolumeUsage, isRoot: Bool)] = urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsLocal ?? false,
                  let total = values.volumeTotalCapacity, total > 0
            else {
                return nil
            }
            let volume = VolumeUsage(
                name: values.volumeLocalizedName ?? url.lastPathComponent,
                path: url.path,
                total: UInt64(total),
                available: UInt64(max(0, values.volumeAvailableCapacityForImportantUsage ?? 0))
            )
            return (volume, values.volumeIsRootFileSystem ?? false)
        }
        return volumes
            .sorted { ($0.isRoot ? 0 : 1, $0.volume.name) < ($1.isRoot ? 0 : 1, $1.volume.name) }
            .prefix(limit)
            .map(\.volume)
    }
}

/// Names and addresses for the interfaces in the network preview.
struct NetworkIdentity: Sendable, Equatable {
    /// BSD name of the interface carrying the default route.
    var primaryInterface: String?
    /// BSD name → "Wi-Fi", "Ethernet", …
    var displayNames: [String: String]
    /// BSD name → first IPv4 address.
    var addresses: [String: String]

    func displayName(for interface: String) -> String {
        displayNames[interface] ?? interface
    }

    static func current() -> NetworkIdentity {
        var primary: String?
        if let store = SCDynamicStoreCreate(nil, "Vibeshed" as CFString, nil, nil),
           let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        {
            primary = global["PrimaryInterface"] as? String
        }
        var names: [String: String] = [:]
        for interface in SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? [] {
            if let bsdName = SCNetworkInterfaceGetBSDName(interface) as String?,
               let displayName = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?
            {
                names[bsdName] = displayName
            }
        }
        return NetworkIdentity(primaryInterface: primary, displayNames: names, addresses: ipv4Addresses())
    }

    private static func ipv4Addresses() -> [String: String] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return [:] }
        defer { freeifaddrs(first) }
        var addresses: [String: String] = [:]
        var cursor = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            guard addresses[name] == nil else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(
                address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST
            ) == 0 {
                addresses[name] = PerformanceProbe.string(fromCString: host)
            }
        }
        return addresses
    }
}
