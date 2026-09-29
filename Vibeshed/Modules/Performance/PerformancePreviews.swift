import SwiftUI

/// Routes a performance action to its preview. Every preview observes the monitor,
/// so it redraws with each sample while it's on screen.
struct PerformancePreview: View {
    let kind: PerformanceAction.Kind
    let monitor: PerformanceMonitor

    var body: some View {
        PreviewLayout(moduleName: "performance") {
            // Sized for the default panel. In a shorter one the content keeps its height
            // and the bottom (the process list) is cut off, rather than every section
            // being squeezed and the header pushed off the top.
            content
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        }
        .reportsPickerVisibility(to: monitor)
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .overview: OverviewPreview(monitor: monitor)
        case .metric(.cpu): CPUPreview(monitor: monitor)
        case .metric(.memory): MemoryPreview(monitor: monitor)
        case .metric(.disk): DiskPreview(monitor: monitor)
        case .metric(.network): NetworkPreview(monitor: monitor)
        }
    }
}

/// The one-line history summary under a chart: average and peak over the window.
struct HistoryStatsRow: View {
    let history: PerformanceHistory
    let series: PerformanceSeries
    let format: (Double) -> String

    var body: some View {
        if let stats = history.stats(series) {
            PreviewMetadataRow(
                icon: "chart.line.uptrend.xyaxis",
                label: "Average · peak",
                value: "\(format(stats.average)) · \(format(stats.peak)) at \(PerformanceFormat.time(stats.peakDate))"
            )
        }
    }
}

// MARK: - Overview

struct OverviewPreview: View {
    let monitor: PerformanceMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MetricHeader(
                title: "System Performance",
                icon: "gauge.with.dots.needle.50percent",
                value: "",
                detail: detail
            )
            ForEach(PerformanceMetric.allCases, id: \.self) { metric in
                OverviewTile(metric: metric, monitor: monitor)
            }
        }
    }

    private var detail: String {
        let hardware = monitor.hardware
        var parts = [hardware.cpuName, PerformanceFormat.memory(hardware.physicalMemory, whole: true)]
        if let boot = hardware.bootDate {
            parts.append("up \(PerformanceFormat.duration(Date().timeIntervalSince(boot)))")
        }
        return parts.joined(separator: " · ")
    }
}

/// A metric's current value over a small chart of its history.
private struct OverviewTile: View {
    let metric: PerformanceMetric
    let monitor: PerformanceMonitor
    @Environment(\.colorScheme) private var colorScheme

    private static let chartPoints = 90

    var body: some View {
        let palette = PerformancePalette(colorScheme: colorScheme)
        let points = monitor.shown.history.downsampled(to: Self.chartPoints, sampleInterval: monitor.sampleInterval)
        let span = max(monitor.shown.history.span, 1)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: metric.iconName)
                    .frame(width: 16)
                Text(metric.shortTitle)
                Spacer(minLength: 8)
                if let sample = monitor.shown.latest {
                    Text(PerformanceSummary.headline(for: metric, sample: sample))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Sparkline(
                points: points,
                series: metric.chartSeries,
                ceiling: metric.sparklineCeiling(for: points[...]),
                span: span,
                gap: max(3 * monitor.sampleInterval, 2.5 * span / Double(Self.chartPoints))
            )
            .foregroundStyle(palette.primary)
            .frame(height: 42)
        }
    }
}

// MARK: - CPU

struct CPUPreview: View {
    let monitor: PerformanceMonitor
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = PerformancePalette(colorScheme: colorScheme)
        let sample = monitor.shown.latest
        let hardware = monitor.hardware
        VStack(alignment: .leading, spacing: 10) {
            MetricHeader(
                title: PerformanceMetric.cpu.title,
                icon: PerformanceMetric.cpu.iconName,
                value: sample.map { PerformanceFormat.percent($0.cpu.usage) } ?? "–",
                detail: "\(hardware.cpuName) · \(hardware.coreSummary(coreCount: sample?.cpu.cores.count ?? 0))"
            )
            HistoryChartSection(
                history: monitor.shown.history,
                sampleInterval: monitor.sampleInterval,
                lines: [
                    ChartLine(name: "Total", series: .cpuUsage, color: palette.primary),
                    ChartLine(name: "System", series: .cpuSystem, color: palette.secondary, filled: false),
                ],
                maxValue: 1,
                format: PerformanceFormat.percent
            )
            if let sample {
                CoreBars(cores: sample.cpu.cores, kinds: hardware.coreKinds, palette: palette)
                VStack(spacing: 5) {
                    PreviewMetadataRow(icon: "gauge.with.needle", label: "Load average", value: Self.load(sample))
                    HistoryStatsRow(
                        history: monitor.shown.history, series: .cpuUsage, format: PerformanceFormat.percent
                    )
                }
            }
            ProcessList(
                title: "Top processes",
                processes: Array(monitor.processes.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(5)),
                value: { PerformanceFormat.decimal($0.cpuPercent, digits: 1) + "%" }
            )
        }
        .whilePickerVisible { await monitor.trackProcesses() }
    }

    /// 1, 5 and 15 minute load averages.
    private static func load(_ sample: PerformanceSample) -> String {
        sample.loadAverage.map { PerformanceFormat.decimal($0, digits: 2) }.joined(separator: "  ")
    }
}

// MARK: - Memory

struct MemoryPreview: View {
    let monitor: PerformanceMonitor
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = PerformancePalette(colorScheme: colorScheme)
        let memory = monitor.shown.latest?.memory
        VStack(alignment: .leading, spacing: 10) {
            MetricHeader(
                title: PerformanceMetric.memory.title,
                icon: PerformanceMetric.memory.iconName,
                value: memory.map { PerformanceFormat.memory($0.used) } ?? "–"
            ) {
                if let memory {
                    HStack(spacing: 4) {
                        Text(Self.share(of: memory) + " ·")
                        PressureLabel(pressure: memory.pressure, palette: palette)
                    }
                } else {
                    Text(PerformanceFormat.memory(monitor.hardware.physicalMemory, whole: true))
                }
            }
            HistoryChartSection(
                history: monitor.shown.history,
                sampleInterval: monitor.sampleInterval,
                lines: [ChartLine(name: "Used", series: .memoryUsed, color: palette.primary)],
                maxValue: 1,
                format: PerformanceFormat.percent
            )
            if let memory {
                MemoryBreakdown(memory: memory, palette: palette)
                VStack(spacing: 5) {
                    PreviewMetadataRow(icon: "arrow.left.arrow.right", label: "Swap used", value: Self.swap(memory))
                    HistoryStatsRow(
                        history: monitor.shown.history, series: .memoryUsed, format: PerformanceFormat.percent
                    )
                }
            }
            ProcessList(
                title: "Top processes",
                processes: Array(monitor.processes.sorted { $0.residentBytes > $1.residentBytes }.prefix(4)),
                value: { PerformanceFormat.memory($0.residentBytes) }
            )
        }
        .whilePickerVisible { await monitor.trackProcesses() }
    }

    /// "82% of 16 GB".
    private static func share(of memory: MemoryReading) -> String {
        "\(PerformanceFormat.percent(memory.usedFraction)) of \(PerformanceFormat.memory(memory.total, whole: true))"
    }

    private static func swap(_ memory: MemoryReading) -> String {
        "\(PerformanceFormat.memory(memory.swapUsed)) of \(PerformanceFormat.memory(memory.swapTotal, whole: true))"
    }
}
