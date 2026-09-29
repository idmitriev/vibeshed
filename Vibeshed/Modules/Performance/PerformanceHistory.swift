import Foundation

/// The part of a sample the charts and their stats need, compact enough (about 48
/// bytes) to keep a day of history at a two-second interval.
struct PerformancePoint: Sendable, Equatable {
    var date: Date
    /// Seconds the rates below were measured over.
    var interval: Float
    var cpuUser: Float
    var cpuSystem: Float
    var memoryUsed: Float
    var memoryPressure: MemoryPressure
    var diskRead: Float
    var diskWrite: Float
    var networkIn: Float
    var networkOut: Float
    /// Charts don't draw across gaps (sleep, a stalled sampler): points on either side
    /// of one get different segments. Set by `PerformanceHistory.downsampled`.
    var segment = 0
}

extension PerformancePoint {
    init(_ sample: PerformanceSample) {
        self.init(
            date: sample.date,
            interval: Float(sample.interval),
            cpuUser: Float(sample.cpu.user),
            cpuSystem: Float(sample.cpu.system),
            memoryUsed: Float(sample.memory.usedFraction),
            memoryPressure: sample.memory.pressure,
            diskRead: Float(sample.disk.readBytesPerSecond),
            diskWrite: Float(sample.disk.writeBytesPerSecond),
            networkIn: Float(sample.network.receivedBytesPerSecond),
            networkOut: Float(sample.network.sentBytesPerSecond)
        )
    }
}

/// A value the history charts: a fraction (0…1) or bytes per second.
enum PerformanceSeries: Sendable, CaseIterable {
    case cpuUsage
    case cpuSystem
    case memoryUsed
    case diskRead
    case diskWrite
    case diskTotal
    case networkIn
    case networkOut
    case networkTotal

    func value(of point: PerformancePoint) -> Double {
        switch self {
        case .cpuUsage: Double(min(1, point.cpuUser + point.cpuSystem))
        case .cpuSystem: Double(point.cpuSystem)
        case .memoryUsed: Double(point.memoryUsed)
        case .diskRead: Double(point.diskRead)
        case .diskWrite: Double(point.diskWrite)
        case .diskTotal: Double(point.diskRead + point.diskWrite)
        case .networkIn: Double(point.networkIn)
        case .networkOut: Double(point.networkOut)
        case .networkTotal: Double(point.networkIn + point.networkOut)
        }
    }
}

struct SeriesStats: Sendable, Equatable {
    var average: Double
    var peak: Double
    var peakDate: Date
}

/// Samples from the last `window` seconds, oldest first.
struct PerformanceHistory: Sendable, Equatable {
    private(set) var points: [PerformancePoint] = []

    mutating func append(_ point: PerformancePoint, window: TimeInterval) {
        points.append(point)
        trim(window: window, now: point.date)
    }

    mutating func trim(window: TimeInterval, now: Date) {
        let cutoff = now.addingTimeInterval(-window)
        guard let first = points.first, first.date < cutoff else { return }
        points.removeFirst(points.firstIndex { $0.date >= cutoff } ?? points.count)
    }

    /// Seconds between the oldest and newest point.
    var span: TimeInterval {
        guard let first = points.first, let last = points.last else { return 0 }
        return last.date.timeIntervalSince(first.date)
    }

    /// Points from the last `duration` seconds before the newest one.
    func recent(_ duration: TimeInterval) -> ArraySlice<PerformancePoint> {
        guard let last = points.last else { return [] }
        let cutoff = last.date.addingTimeInterval(-duration)
        let start = points.lastIndex { $0.date < cutoff }.map { $0 + 1 } ?? 0
        return points[start...]
    }

    func stats(_ series: PerformanceSeries) -> SeriesStats? {
        guard let first = points.first else { return nil }
        var sum = 0.0
        var peak = series.value(of: first)
        var peakDate = first.date
        for point in points {
            let value = series.value(of: point)
            sum += value
            if value > peak {
                peak = value
                peakDate = point.date
            }
        }
        return SeriesStats(average: sum / Double(points.count), peak: peak, peakDate: peakDate)
    }

    /// Bytes moved over the whole history, for a bytes-per-second series.
    func total(_ series: PerformanceSeries) -> Double {
        points.reduce(0) { $0 + series.value(of: $1) * Double($1.interval) }
    }

    /// At most `count` points for a chart, each averaging an equal slice of time (a
    /// slice's pressure is its worst). Two neighbours further apart than a few sampling
    /// intervals — or bucket widths — sit on either side of a gap and get different segments.
    func downsampled(to count: Int, sampleInterval: TimeInterval) -> [PerformancePoint] {
        guard let first = points.first, count > 0 else { return [] }
        var result: [PerformancePoint]
        var bucketWidth = 0.0
        if points.count <= count {
            result = points
        } else {
            bucketWidth = span / Double(count)
            var buckets = [Bucket](repeating: Bucket(), count: count)
            for point in points {
                let offset = point.date.timeIntervalSince(first.date)
                buckets[min(count - 1, Int(offset / bucketWidth))].add(point)
            }
            result = buckets.compactMap(\.average)
        }

        let gap = max(3 * sampleInterval, 2.5 * bucketWidth)
        var segment = 0
        for index in result.indices {
            if index > 0, result[index].date.timeIntervalSince(result[index - 1].date) > gap {
                segment += 1
            }
            result[index].segment = segment
        }
        return result
    }

    private struct Bucket {
        var members = 0
        var dateSum = 0.0
        var interval: Float = 0
        var cpuUser: Float = 0
        var cpuSystem: Float = 0
        var memoryUsed: Float = 0
        var pressure = MemoryPressure.normal
        var diskRead: Float = 0
        var diskWrite: Float = 0
        var networkIn: Float = 0
        var networkOut: Float = 0

        mutating func add(_ point: PerformancePoint) {
            members += 1
            dateSum += point.date.timeIntervalSinceReferenceDate
            interval += point.interval
            cpuUser += point.cpuUser
            cpuSystem += point.cpuSystem
            memoryUsed += point.memoryUsed
            pressure = max(pressure, point.memoryPressure)
            diskRead += point.diskRead
            diskWrite += point.diskWrite
            networkIn += point.networkIn
            networkOut += point.networkOut
        }

        var average: PerformancePoint? {
            guard members > 0 else { return nil }
            let divisor = Float(members)
            return PerformancePoint(
                date: Date(timeIntervalSinceReferenceDate: dateSum / Double(members)),
                interval: interval,
                cpuUser: cpuUser / divisor,
                cpuSystem: cpuSystem / divisor,
                memoryUsed: memoryUsed / divisor,
                memoryPressure: pressure,
                diskRead: diskRead / divisor,
                diskWrite: diskWrite / divisor,
                networkIn: networkIn / divisor,
                networkOut: networkOut / divisor
            )
        }
    }
}
