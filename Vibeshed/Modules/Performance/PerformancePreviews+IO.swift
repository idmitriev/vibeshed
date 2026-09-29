import SwiftUI

// MARK: - Disk

struct DiskPreview: View {
    let monitor: PerformanceMonitor
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = PerformancePalette(colorScheme: colorScheme)
        let disk = monitor.shown.latest?.disk
        VStack(alignment: .leading, spacing: 10) {
            MetricHeader(
                title: PerformanceMetric.disk.title,
                icon: PerformanceMetric.disk.iconName,
                value: disk.map { PerformanceFormat.rate($0.bytesPerSecond) } ?? "–",
                detail: startupVolume
            )
            HistoryChartSection(
                history: monitor.shown.history,
                sampleInterval: monitor.sampleInterval,
                lines: [
                    ChartLine(name: "Read", series: .diskRead, color: palette.primary),
                    ChartLine(name: "Write", series: .diskWrite, color: palette.secondary),
                ],
                maxValue: nil,
                format: PerformanceFormat.rate
            )
            if let disk {
                VStack(spacing: 5) {
                    PreviewMetadataRow(icon: "arrow.down.circle", label: "Read", value: Self.rate(disk, read: true))
                    PreviewMetadataRow(icon: "arrow.up.circle", label: "Write", value: Self.rate(disk, read: false))
                    HistoryStatsRow(
                        history: monitor.shown.history, series: .diskTotal, format: PerformanceFormat.rate
                    )
                    PreviewMetadataRow(
                        icon: "sum",
                        label: "Since boot",
                        value: "\(PerformanceFormat.bytes(Double(disk.totalRead))) read · "
                            + "\(PerformanceFormat.bytes(Double(disk.totalWritten))) written"
                    )
                }
            }
            if !monitor.volumes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SectionTitle("Volumes")
                    ForEach(monitor.volumes.prefix(2)) { volume in
                        VolumeRow(volume: volume, palette: palette)
                    }
                }
            }
        }
        .whilePickerVisible { await monitor.refreshVolumes() }
    }

    /// "57 GB free on Macintosh HD", once the volumes are in.
    private var startupVolume: String {
        guard let volume = monitor.volumes.first else { return "All disks" }
        return "\(PerformanceFormat.bytes(Double(volume.available))) free on \(volume.name)"
    }

    /// "12 MB/s · 340 ops/s".
    private static func rate(_ disk: DiskReading, read: Bool) -> String {
        let bytes = read ? disk.readBytesPerSecond : disk.writeBytesPerSecond
        let operations = read ? disk.readsPerSecond : disk.writesPerSecond
        return "\(PerformanceFormat.rate(bytes)) · \(PerformanceFormat.decimal(operations)) ops/s"
    }
}

private struct VolumeRow: View {
    let volume: VolumeUsage
    let palette: PerformancePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(volume.name)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(capacity)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            UsageMeter(fraction: volume.usedFraction, palette: palette)
        }
    }

    /// "57 GB free of 494 GB".
    private var capacity: String {
        "\(PerformanceFormat.bytes(Double(volume.available))) free of \(PerformanceFormat.bytes(Double(volume.total)))"
    }
}

// MARK: - Network

struct NetworkPreview: View {
    let monitor: PerformanceMonitor
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = PerformancePalette(colorScheme: colorScheme)
        let network = monitor.shown.latest?.network
        VStack(alignment: .leading, spacing: 10) {
            MetricHeader(
                title: PerformanceMetric.network.title,
                icon: PerformanceMetric.network.iconName,
                value: network.map { PerformanceFormat.rate($0.bytesPerSecond) } ?? "–",
                detail: primaryInterface
            )
            HistoryChartSection(
                history: monitor.shown.history,
                sampleInterval: monitor.sampleInterval,
                lines: [
                    ChartLine(name: "Down", series: .networkIn, color: palette.primary),
                    ChartLine(name: "Up", series: .networkOut, color: palette.secondary),
                ],
                maxValue: nil,
                format: PerformanceFormat.rate
            )
            if let network {
                VStack(spacing: 5) {
                    PreviewMetadataRow(
                        icon: "arrow.down.circle",
                        label: "Download",
                        value: PerformanceFormat.rate(network.receivedBytesPerSecond)
                    )
                    PreviewMetadataRow(
                        icon: "arrow.up.circle",
                        label: "Upload",
                        value: PerformanceFormat.rate(network.sentBytesPerSecond)
                    )
                    PreviewMetadataRow(
                        icon: "sum",
                        label: "Last \(PerformanceFormat.span(monitor.shown.history.span))",
                        value: "\(PerformanceFormat.bytes(monitor.shown.history.total(.networkIn))) down · "
                            + "\(PerformanceFormat.bytes(monitor.shown.history.total(.networkOut))) up"
                    )
                    HistoryStatsRow(
                        history: monitor.shown.history, series: .networkTotal, format: PerformanceFormat.rate
                    )
                }
                // Only when traffic is split: idle interfaces (Thunderbolt ports, AWDL)
                // would fill it with zeros, and one busy interface is already the header.
                let busy = network.interfaces.filter { $0.bytesPerSecond > 0 }
                if busy.count > 1 {
                    VStack(alignment: .leading, spacing: 3) {
                        SectionTitle("Interfaces")
                        ForEach(busy.prefix(3)) { interface in
                            InterfaceRow(interface: interface, identity: monitor.networkIdentity)
                        }
                    }
                }
            }
        }
        .whilePickerVisible { await monitor.refreshNetworkIdentity() }
    }

    /// "Wi-Fi · 192.168.1.23", once the names are in.
    private var primaryInterface: String {
        guard let identity = monitor.networkIdentity, let primary = identity.primaryInterface else {
            return "All interfaces"
        }
        return [identity.displayName(for: primary), identity.addresses[primary]]
            .compactMap(\.self)
            .joined(separator: " · ")
    }
}

private struct InterfaceRow: View {
    let interface: InterfaceReading
    let identity: NetworkIdentity?

    var body: some View {
        HStack(spacing: 8) {
            Text(name)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(rates)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    /// "↓ 1.2 MB/s  ↑ 80 KB/s".
    private var rates: String {
        "↓ \(PerformanceFormat.rate(interface.receivedBytesPerSecond))  "
            + "↑ \(PerformanceFormat.rate(interface.sentBytesPerSecond))"
    }

    private var name: String {
        guard let identity, let displayName = identity.displayNames[interface.name] else {
            return interface.name
        }
        return "\(displayName) (\(interface.name))"
    }
}
