import SwiftUI

// MARK: - Picker visibility

extension View {
    /// Lets the monitor stop refreshing the views while the picker is hidden.
    func reportsPickerVisibility(to monitor: PerformanceMonitor) -> some View {
        modifier(PickerVisibilityReporter(monitor: monitor))
    }

    /// Runs `work` while the picker is on screen: started when it shows, cancelled when
    /// it hides or the view goes away.
    func whilePickerVisible(_ work: @escaping @MainActor @Sendable () async -> Void) -> some View {
        modifier(WhilePickerVisible(work: work))
    }
}

private struct PickerVisibilityReporter: ViewModifier {
    let monitor: PerformanceMonitor
    @Environment(\.isPickerVisible) private var isPickerVisible

    func body(content: Content) -> some View {
        content.onChange(of: isPickerVisible, initial: true) { _, visible in
            monitor.setDisplayed(visible)
        }
    }
}

private struct WhilePickerVisible: ViewModifier {
    let work: @MainActor @Sendable () async -> Void
    @Environment(\.isPickerVisible) private var isPickerVisible

    func body(content: Content) -> some View {
        content.task(id: isPickerVisible) {
            if isPickerVisible {
                await work()
            }
        }
    }
}

// MARK: - Header

/// Title, what's being measured, and the current value as the preview's lead figure.
struct MetricHeader<Detail: View>: View {
    let title: String
    let icon: String
    let value: String
    @ViewBuilder let detail: () -> Detail

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                detail()
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            // A wide value shrinks (down to 60%) before the detail line is cut short.
            .layoutPriority(1)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 28, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
    }
}

extension MetricHeader where Detail == Text {
    init(title: String, icon: String, value: String, detail: String) {
        self.init(title: title, icon: icon, value: value) { Text(detail) }
    }
}

struct SectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

/// A status value: the color never carries the meaning alone, so an icon and a label
/// come with it.
struct PressureLabel: View {
    let pressure: MemoryPressure
    let palette: PerformancePalette

    var body: some View {
        Label {
            Text(pressure.label)
        } icon: {
            Image(systemName: pressure == .normal ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(palette.pressure(pressure))
        }
    }
}

// MARK: - Processes

/// The busiest processes by one measure, name and value on a line each.
struct ProcessList: View {
    let title: String
    let processes: [ProcessUsage]
    let value: (ProcessUsage) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionTitle(title)
            if processes.isEmpty {
                Text("Loading…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            ForEach(processes) { process in
                HStack(spacing: 8) {
                    Text(process.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(value(process))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }
}

// MARK: - Meters

/// One bar per logical core, grouped by core type where the hardware says.
struct CoreBars: View {
    let cores: [Double]
    let kinds: [CoreKind]
    let palette: PerformancePalette

    private struct Group: Identifiable {
        let id: Int
        let label: String?
        let usage: [Double]
    }

    private static let barHeight: CGFloat = 18
    private static let groupSpacing: CGFloat = 10

    var body: some View {
        let coreGroups = groups
        let hasLabels = coreGroups.contains { $0.label != nil }
        GeometryReader { geometry in
            // Every core gets an equal slot across the full width; bars are capped at
            // 24pt and centered in their slot, so the leftover is air between them.
            let spacing = Self.groupSpacing * CGFloat(coreGroups.count - 1)
            let slot = max(1, (geometry.size.width - spacing) / CGFloat(max(1, cores.count)))
            HStack(alignment: .top, spacing: Self.groupSpacing) {
                ForEach(coreGroups) { group in
                    VStack(spacing: 2) {
                        HStack(spacing: 0) {
                            ForEach(Array(group.usage.enumerated()), id: \.offset) { _, usage in
                                bar(usage)
                                    .frame(width: min(24, max(1, slot - 2)))
                                    .frame(width: slot)
                            }
                        }
                        .frame(height: Self.barHeight)
                        if let label = group.label {
                            Text(label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .frame(height: hasLabels ? Self.barHeight + 16 : Self.barHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Per-core usage")
        .accessibilityValue(cores.map { PerformanceFormat.percent($0) }.joined(separator: ", "))
    }

    /// A track with the used part growing from the baseline; the data end is rounded.
    private func bar(_ usage: Double) -> some View {
        ZStack(alignment: .bottom) {
            UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
                .fill(palette.track)
            UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
                .fill(palette.primary)
                .frame(height: max(1, Self.barHeight * min(1, usage)))
        }
    }

    private var groups: [Group] {
        guard kinds.count == cores.count, Set(kinds).count > 1 else {
            return [Group(id: 0, label: nil, usage: cores)]
        }
        var groups: [Group] = []
        var start = 0
        while start < cores.count {
            let kind = kinds[start]
            var end = start
            while end < cores.count, kinds[end] == kind {
                end += 1
            }
            let label = kind == .efficiency ? "Efficiency" : "Performance"
            groups.append(Group(id: start, label: label, usage: Array(cores[start ..< end])))
            start = end
        }
        return groups
    }
}

/// A horizontal meter: the filled part in the primary hue over a track of the same hue.
struct UsageMeter: View {
    let fraction: Double
    let palette: PerformancePalette

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.track)
                Capsule()
                    .fill(palette.primary)
                    .frame(width: max(4, geometry.size.width * min(1, fraction)))
            }
        }
        .frame(height: 4)
    }
}

/// Physical memory as one stacked bar (app, wired, compressed, cached files; the rest
/// is free), with a legend that names every segment and its size.
struct MemoryBreakdown: View {
    let memory: MemoryReading
    let palette: PerformancePalette

    private struct Segment: Identifiable {
        let name: String
        let bytes: UInt64
        let color: Color

        var id: String {
            name
        }
    }

    private var segments: [Segment] {
        [
            Segment(name: "App", bytes: memory.app, color: palette.primary),
            Segment(name: "Wired", bytes: memory.wired, color: palette.secondary),
            Segment(name: "Compressed", bytes: memory.compressed, color: palette.tertiary),
            Segment(name: "Cached files", bytes: memory.cachedFiles, color: palette.quaternary),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                let visible = segments.filter { $0.bytes > 0 }
                // Segments are separated by 2pt of the surface, not by strokes.
                let gaps = CGFloat(max(0, visible.count - 1)) * 2
                let scale = (geometry.size.width - gaps) / CGFloat(max(1, memory.total))
                HStack(spacing: 2) {
                    ForEach(visible) { segment in
                        Rectangle()
                            .fill(segment.color)
                            .frame(width: max(1, CGFloat(segment.bytes) * scale))
                    }
                    Spacer(minLength: 0)
                }
                .background(palette.track)
                .clipShape(Capsule())
            }
            .frame(height: 8)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                GridRow {
                    legendEntry(segments[0])
                    legendEntry(segments[1])
                }
                GridRow {
                    legendEntry(segments[2])
                    legendEntry(segments[3])
                }
            }
        }
    }

    private func legendEntry(_ segment: Segment) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(segment.color)
                .frame(width: 8, height: 8)
            Text(segment.name)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(PerformanceFormat.memory(segment.bytes))
                .monospacedDigit()
        }
        .font(.caption)
    }
}
