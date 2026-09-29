import Charts
import SwiftUI

/// One line in a history chart, with an optional 12% wash under it.
struct ChartLine: Identifiable {
    let name: String
    let series: PerformanceSeries
    let color: Color
    var filled = true

    var id: String {
        name
    }
}

/// A history chart with a caption row above it. The row shows the time span and a
/// legend; while the pointer is over the chart it becomes the readout for that moment.
struct HistoryChartSection: View {
    let history: PerformanceHistory
    let sampleInterval: TimeInterval
    let lines: [ChartLine]
    /// Top of the scale: 1 for fractions; `nil` scales rates to their peak.
    let maxValue: Double?
    let format: (Double) -> String
    var height: CGFloat = 76

    @State private var hovered: PerformancePoint?

    /// Enough points for a smooth line at the preview's width.
    private static let chartPoints = 120

    var body: some View {
        let points = history.downsampled(to: Self.chartPoints, sampleInterval: sampleInterval)
        VStack(alignment: .leading, spacing: 4) {
            caption
            if points.count >= 2 {
                PerformanceHistoryChart(
                    points: points,
                    lines: lines,
                    maxValue: maxValue ?? ChartScale.niceCeiling(peak(of: points)),
                    format: format,
                    hovered: $hovered
                )
                .frame(height: height)
            } else {
                Text("Collecting samples…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: height)
            }
        }
    }

    private var caption: some View {
        HStack(spacing: 10) {
            if let hovered {
                Text(PerformanceFormat.time(hovered.date))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                ForEach(lines) { line in
                    legendKey(line.color) {
                        // The value leads; the series name follows in a quieter color.
                        Text(format(line.series.value(of: hovered)))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                        Text(line.name.lowercased())
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Last \(PerformanceFormat.span(history.span))")
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer(minLength: 4)
                if lines.count > 1 {
                    ForEach(lines) { line in
                        legendKey(line.color) {
                            Text(line.name).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .font(.caption2)
        .lineLimit(1)
    }

    /// Legend and readout entries are keyed with a short stroke of the line's color;
    /// the text stays in text colors.
    private func legendKey(_ color: Color, @ViewBuilder label: () -> some View) -> some View {
        HStack(spacing: 4) {
            Capsule()
                .fill(color)
                .frame(width: 10, height: 2)
            label()
        }
    }

    private func peak(of points: [PerformancePoint]) -> Double {
        points.reduce(0) { peak, point in
            lines.reduce(peak) { max($0, $1.series.value(of: point)) }
        }
    }
}

/// Where rate scales top out.
enum ChartScale {
    /// The smallest top of a rate scale. Background disk and network chatter sits in the
    /// kilobytes; scaled to its own peak it would look like load.
    static let rateFloor: Double = 1_000_000

    /// Rounds a rate up to 1, 2 or 5 × 10ⁿ bytes per second for round gridline labels,
    /// and to at least `rateFloor`.
    static func niceCeiling(_ value: Double) -> Double {
        let value = max(value, rateFloor)
        let magnitude = pow(10, floor(log10(value)))
        for step in [1.0, 2.0, 5.0] where value <= step * magnitude {
            return step * magnitude
        }
        return 10 * magnitude
    }
}

/// The chart itself: 2pt lines with washes, recessive trailing gridlines, and a hover
/// crosshair that snaps to the nearest point.
struct PerformanceHistoryChart: View {
    let points: [PerformancePoint]
    let lines: [ChartLine]
    let maxValue: Double
    let format: (Double) -> String
    @Binding var hovered: PerformancePoint?

    var body: some View {
        Chart {
            // Drawn back to front, so the first (main) line stays on top where they meet.
            ForEach(lines.reversed()) { line in
                ForEach(points, id: \.date) { point in
                    let value = line.series.value(of: point)
                    let series = "\(line.name) \(point.segment)"
                    if line.filled {
                        AreaMark(
                            x: .value("Time", point.date),
                            yStart: .value("Base", 0),
                            yEnd: .value(line.name, value),
                            series: .value("Series", series)
                        )
                        .foregroundStyle(line.color.opacity(0.12))
                    }
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value(line.name, value),
                        series: .value("Series", series)
                    )
                    .foregroundStyle(line.color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
            if let hovered {
                RuleMark(x: .value("Time", hovered.date))
                    .foregroundStyle(Color.primary.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                ForEach(lines) { line in
                    PointMark(
                        x: .value("Time", hovered.date),
                        y: .value(line.name, line.series.value(of: hovered))
                    )
                    .symbol {
                        // An 8pt dot in a 2pt ring of the surface, legible where lines cross.
                        Circle()
                            .fill(line.color)
                            .frame(width: 8, height: 8)
                            .padding(2)
                            .background(Circle().fill(.background))
                    }
                }
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: 0 ... maxValue)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, maxValue / 2, maxValue]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.primary.opacity(0.12))
                AxisValueLabel {
                    if let number = value.as(Double.self), number > 0 {
                        Text(format(number))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case let .active(location):
                            guard let plotFrame = proxy.plotFrame else { return }
                            let x = location.x - geometry[plotFrame].origin.x
                            hovered = proxy.value(atX: x, as: Date.self).flatMap(nearestPoint)
                        case .ended:
                            hovered = nil
                        }
                    }
            }
        }
        .accessibilityLabel(lines.map(\.name).joined(separator: " and "))
    }

    private var xDomain: ClosedRange<Date> {
        guard let first = points.first?.date, let last = points.last?.date, last > first else {
            let now = points.last?.date ?? Date()
            return now.addingTimeInterval(-60) ... now
        }
        return first ... last
    }

    private func nearestPoint(to date: Date) -> PerformancePoint? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}
