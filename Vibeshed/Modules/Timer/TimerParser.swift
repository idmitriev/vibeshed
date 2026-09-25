import Foundation

enum TimerParser {
    // MARK: - Duration Parsing

    static func parseDuration(_ input: String) -> TimeInterval? {
        let trimmed = input.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).lowercased()
        guard !trimmed.isEmpty else { return nil }

        // "1:30" format → minutes:seconds
        if let colonIndex = trimmed.firstIndex(of: ":"),
           !trimmed.contains("h"), !trimmed.contains("m"),
           !trimmed.contains("s")
        {
            return parseMinutesSeconds(trimmed, colonIndex: colonIndex)
        }

        // "1h30m", "5m", "90s", "1h"
        var total: TimeInterval = 0
        var current = ""
        var hasUnit = false

        for char in trimmed {
            if char.isNumber || char == "." {
                current += String(char)
            } else if let unitSeconds = durationUnits[char] {
                guard let val = Double(current) else { return nil }
                total += val * unitSeconds
                current = ""
                hasUnit = true
            } else if !char.isWhitespace {
                return nil
            }
        }

        // Remaining number without unit → treat as minutes
        if !current.isEmpty {
            guard let val = Double(current) else { return nil }
            total += val * 60
        }

        guard hasUnit || !current.isEmpty else { return nil }
        return total > 0 ? total : nil
    }

    /// Seconds per unit letter in compact durations like "1h30m".
    private static let durationUnits: [Character: TimeInterval] = ["h": 3600, "m": 60, "s": 1]

    /// "1:30" → 90 seconds; nil unless both parts are whole numbers and seconds < 60.
    private static func parseMinutesSeconds(_ input: String, colonIndex: String.Index) -> TimeInterval? {
        let minStr = String(input[..<colonIndex])
        let secStr = String(input[input.index(after: colonIndex)...])
        guard let mins = Int(minStr), let secs = Int(secStr),
              mins >= 0, secs >= 0, secs < 60
        else {
            return nil
        }
        return TimeInterval(mins * 60 + secs)
    }

    // MARK: - Time Parsing

    static func parseTime(_ input: String) -> Date? {
        let trimmed = input.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).lowercased()
        guard !trimmed.isEmpty else { return nil }

        // "in X hours/minutes" format
        if trimmed.hasPrefix("in ") {
            return parseRelativeTime(String(trimmed.dropFirst(3)))
        }

        // Time formats: "3:00 PM", "3pm", "15:00"
        return parseAbsoluteTime(trimmed)
    }

    private static func parseRelativeTime(
        _ input: String
    ) -> Date? {
        let trimmed = input.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        var total: TimeInterval = 0
        var current = ""

        for char in trimmed {
            if char.isNumber || char == "." {
                current += String(char)
            } else if !char.isWhitespace {
                let rest = String(
                    trimmed[trimmed.index(
                        trimmed.startIndex,
                        offsetBy: trimmed.distance(
                            from: trimmed.startIndex,
                            to: trimmed.firstIndex(of: char)
                                ?? trimmed.endIndex
                        )
                    )...]
                ).trimmingCharacters(in: .whitespaces)
                if !current.isEmpty, let val = Double(current),
                   let unit = relativeUnits.first(where: { rest.hasPrefix($0.prefix) })
                {
                    total += val * unit.seconds
                }
                break
            }
        }

        // Just a number → treat as hours
        if total == 0, !current.isEmpty, let val = Double(current) {
            total = val * 3600
        }

        return total > 0 ? Date().addingTimeInterval(total) : nil
    }

    /// Unit words for "in 2 hours"-style input, matched by prefix in this order.
    private static let relativeUnits: [(prefix: String, seconds: TimeInterval)] = [
        ("hour", 3600), ("hr", 3600), ("min", 60), ("sec", 1),
        ("h", 3600), ("m", 60), ("s", 1),
    ]

    private static func parseAbsoluteTime(
        _ input: String
    ) -> Date? {
        let now = Date()
        let calendar = Calendar.current

        let formats = [
            "h:mm a", "h:mma", "ha", "h a",
            "HH:mm", "H:mm",
        ]

        for format in formats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            if let parsed = formatter.date(from: input) {
                let components = calendar.dateComponents(
                    [.hour, .minute],
                    from: parsed
                )
                guard let hour = components.hour,
                      let minute = components.minute
                else { continue }

                var target = calendar.dateComponents(
                    [.year, .month, .day],
                    from: now
                )
                target.hour = hour
                target.minute = minute
                target.second = 0

                guard var date = calendar.date(from: target) else {
                    continue
                }

                // If time is in the past, schedule for tomorrow
                if date <= now {
                    date = calendar.date(
                        byAdding: .day, value: 1, to: date
                    ) ?? date
                }

                return date
            }
        }

        return nil
    }

    // MARK: - Formatting

    static func formatCountdown(
        _ seconds: TimeInterval
    ) -> String {
        let totalSeconds = max(0, Int(seconds))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(
                format: "%d:%02d:%02d", hours, minutes, secs
            )
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func formatDurationLong(
        _ seconds: TimeInterval
    ) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0, minutes > 0 {
            return "\(hours) hour\(hours == 1 ? "" : "s") \(minutes) min"
        } else if hours > 0 {
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        } else if minutes > 0 {
            return "\(minutes) min"
        } else {
            return "\(totalSeconds) sec"
        }
    }
}
