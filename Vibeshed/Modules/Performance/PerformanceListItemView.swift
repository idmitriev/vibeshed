import SwiftUI

/// Chart colors: the first four categorical slots of the validated dataviz reference
/// palette and its status steps, each stepped for light and dark surfaces.
struct PerformancePalette {
    let colorScheme: ColorScheme

    private var isDark: Bool {
        colorScheme == .dark
    }

    /// Blue: the main series of every chart.
    var primary: Color {
        Color(hex: isDark ? 0x3987E5 : 0x2A78D6)
    }

    /// Orange: the second series (system time, writes, uploads).
    var secondary: Color {
        Color(hex: isDark ? 0xD95926 : 0xEB6834)
    }

    /// Aqua.
    var tertiary: Color {
        Color(hex: isDark ? 0x199E70 : 0x1BAF7A)
    }

    /// Yellow.
    var quaternary: Color {
        Color(hex: isDark ? 0xC98500 : 0xEDA100)
    }

    /// The unfilled part of a meter: a faint step of the fill's own hue.
    var track: Color {
        primary.opacity(isDark ? 0.22 : 0.16)
    }

    func pressure(_ level: MemoryPressure) -> Color {
        switch level {
        case .normal: Color(hex: 0x0CA30C)
        case .warning: Color(hex: 0xFAB219)
        case .critical: Color(hex: 0xD03B3B)
        }
    }
}

private extension Color {
    /// An sRGB color from `0xRRGGBB`.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - List row

/// A picker row whose subtitle and sparkline follow the live samples.
struct PerformanceListItemView: View {
    let action: PerformanceAction

    /// The row's sparkline covers the last two minutes.
    private static let sparklineSpan: TimeInterval = 120

    var body: some View {
        let monitor = action.monitor
        HStack(spacing: 12) {
            Image(systemName: action.iconName ?? "gauge.with.dots.needle.50percent")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.body)
                    .lineLimit(1)
                Text(PerformanceSummary.line(for: action.kind, sample: monitor.shown.latest))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if case let .metric(metric) = action.kind {
                let recent = monitor.shown.history.recent(Self.sparklineSpan)
                Sparkline(
                    points: Array(recent),
                    series: metric.chartSeries,
                    ceiling: metric.sparklineCeiling(for: recent),
                    span: Self.sparklineSpan,
                    gap: 3 * monitor.sampleInterval
                )
                .foregroundStyle(.secondary)
                .frame(width: 72, height: 24)
                .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .reportsPickerVisibility(to: monitor)
    }
}

extension PerformanceMetric {
    /// The series the sparklines and the overview draw.
    var chartSeries: PerformanceSeries {
        switch self {
        case .cpu: .cpuUsage
        case .memory: .memoryUsed
        case .disk: .diskTotal
        case .network: .networkTotal
        }
    }

    /// Top of a sparkline's scale. Rates scale to their peak, but no lower than the
    /// charts' floor, so an idle disk or network draws flat.
    func sparklineCeiling(for points: ArraySlice<PerformancePoint>) -> Double {
        switch self {
        case .cpu, .memory:
            return 1
        case .disk, .network:
            let peak = points.map { chartSeries.value(of: $0) }.max() ?? 0
            return max(peak, ChartScale.rateFloor)
        }
    }
}

// MARK: - Sparkline

/// A line with a faint wash under it, positioned by time, so a gap in the samples
/// stays a gap. It draws in the foreground style, so it follows the row's selected color.
struct Sparkline: View {
    let points: [PerformancePoint]
    let series: PerformanceSeries
    let ceiling: Double
    /// Seconds the width covers, ending at the newest point.
    let span: TimeInterval
    /// Neighbours further apart than this aren't connected (sleep, a stalled sampler).
    let gap: TimeInterval

    var body: some View {
        let stretches = runs
        ZStack {
            SparklineShape(runs: stretches)
                .fill()
                .opacity(0.18)
            SparklineShape(runs: stretches, closed: false)
                .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }

    /// Unbroken stretches of points in unit space.
    private var runs: [[CGPoint]] {
        guard let end = points.last?.date, ceiling > 0, span > 0 else { return [] }
        let start = end.addingTimeInterval(-span)
        var runs: [[CGPoint]] = []
        var previous: Date?
        for point in points {
            let position = CGPoint(
                x: point.date.timeIntervalSince(start) / span,
                y: min(1, series.value(of: point) / ceiling)
            )
            if let previous, point.date.timeIntervalSince(previous) <= gap {
                runs[runs.count - 1].append(position)
            } else {
                runs.append([position])
            }
            previous = point.date
        }
        return runs
    }
}

/// Runs of unit-space points (x and y in 0…1, y up), each drawn as a line or closed
/// down to the baseline for the wash.
struct SparklineShape: Shape {
    var runs: [[CGPoint]]
    var closed = true

    func path(in rect: CGRect) -> Path {
        var path = Path()
        func position(_ point: CGPoint) -> CGPoint {
            CGPoint(x: rect.minX + point.x * rect.width, y: rect.maxY - point.y * rect.height)
        }
        for run in runs {
            guard let first = run.first, let last = run.last else { continue }
            path.move(to: position(first))
            for point in run.dropFirst() {
                path.addLine(to: position(point))
            }
            if closed {
                path.addLine(to: CGPoint(x: rect.minX + last.x * rect.width, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX + first.x * rect.width, y: rect.maxY))
                path.closeSubpath()
            }
        }
        return path
    }
}
