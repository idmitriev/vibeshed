import Foundation

enum PerformanceFormat {
    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    /// Decimal units, as Activity Monitor shows disk and network figures: "1.2 MB".
    static func bytes(_ value: Double) -> String {
        scaled(value, base: 1000, decimalsBelow: 9.95)
    }

    /// Binary units, the way memory is sized, with a decimal up to 100: "13.1 GB".
    /// `whole` leaves the decimal off, for sizes like installed memory ("16 GB").
    static func memory(_ value: UInt64, whole: Bool = false) -> String {
        scaled(Double(value), base: 1024, decimalsBelow: whole ? 0 : 99.95)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        bytes(bytesPerSecond) + "/s"
    }

    static func decimal(_ value: Double, digits: Int = 0) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }

    /// "6d 16h", "3h 12m", "12m".
    static func duration(_ interval: TimeInterval) -> String {
        Duration.seconds(max(0, interval)).formatted(
            .units(allowed: [.days, .hours, .minutes], width: .narrow, maximumUnitCount: 2)
        )
    }

    /// "1 hr", "5 min", "40 sec".
    static func span(_ interval: TimeInterval) -> String {
        Duration.seconds(max(1, interval.rounded())).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 1)
        )
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// Values under `decimalsBelow` (in the chosen unit) get one decimal; bytes never do.
    private static func scaled(_ value: Double, base: Double, decimalsBelow: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var scaled = max(0, value)
        var unit = 0
        while scaled >= 999.5, unit < units.count - 1 {
            scaled /= base
            unit += 1
        }
        let digits = unit > 0 && scaled < decimalsBelow ? 1 : 0
        return decimal(scaled, digits: digits) + " " + units[unit]
    }
}

/// The one-line summaries shared by the action subtitles and the live list rows.
enum PerformanceSummary {
    static func headline(for metric: PerformanceMetric, sample: PerformanceSample) -> String {
        switch metric {
        case .cpu: PerformanceFormat.percent(sample.cpu.usage)
        case .memory: PerformanceFormat.memory(sample.memory.used)
        case .disk: PerformanceFormat.rate(sample.disk.bytesPerSecond)
        case .network: PerformanceFormat.rate(sample.network.bytesPerSecond)
        }
    }

    static func line(for kind: PerformanceAction.Kind, sample: PerformanceSample?) -> String {
        guard let sample else { return "Measuring…" }
        switch kind {
        case .overview:
            return [
                "CPU \(PerformanceFormat.percent(sample.cpu.usage))",
                "Memory \(PerformanceFormat.percent(sample.memory.usedFraction))",
                "Disk \(PerformanceFormat.rate(sample.disk.bytesPerSecond))",
                "Network \(PerformanceFormat.rate(sample.network.bytesPerSecond))",
            ].joined(separator: " · ")
        case .metric(.cpu):
            var parts = [
                headline(for: .cpu, sample: sample),
                "User \(PerformanceFormat.percent(sample.cpu.user))",
                "System \(PerformanceFormat.percent(sample.cpu.system))",
            ]
            if let load = sample.loadAverage.first {
                parts.append("Load \(PerformanceFormat.decimal(load, digits: 2))")
            }
            return parts.joined(separator: " · ")
        case .metric(.memory):
            let memory = sample.memory
            return [
                "\(headline(for: .memory, sample: sample)) of \(PerformanceFormat.memory(memory.total, whole: true))",
                "Pressure \(memory.pressure.label.lowercased())",
                "Swap \(PerformanceFormat.memory(memory.swapUsed))",
            ].joined(separator: " · ")
        case .metric(.disk):
            return [
                "Read \(PerformanceFormat.rate(sample.disk.readBytesPerSecond))",
                "Write \(PerformanceFormat.rate(sample.disk.writeBytesPerSecond))",
            ].joined(separator: " · ")
        case .metric(.network):
            return [
                "Down \(PerformanceFormat.rate(sample.network.receivedBytesPerSecond))",
                "Up \(PerformanceFormat.rate(sample.network.sentBytesPerSecond))",
            ].joined(separator: " · ")
        }
    }
}
