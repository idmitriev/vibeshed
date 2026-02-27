import SwiftUI

struct CalendarActionListItemView: View {
    let action: CalendarAction

    var body: some View {
        HStack(spacing: 12) {
            calendarIcon
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.body)
                    .lineLimit(1)

                if !action.subtitle.isEmpty {
                    Text(action.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if action.calendarItemType == .event, let start = action.startDate {
                timeBadge(for: start, endDate: action.endDate)
            }

            if action.videoLinkType != nil {
                Image(systemName: "video.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var calendarIcon: some View {
        switch action.calendarItemType {
        case .event:
            ZStack {
                Circle()
                    .fill(calendarColor.opacity(0.2))
                    .frame(width: 28, height: 28)
                Circle()
                    .fill(calendarColor)
                    .frame(width: 10, height: 10)
            }
        case .utility:
            Image(systemName: action.iconName ?? "calendar")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var calendarColor: Color {
        if let hex = action.calendarColorHex {
            return Color(calendarHex: hex)
        }
        return .blue
    }

    @ViewBuilder
    private func timeBadge(
        for start: Date,
        endDate: Date?
    ) -> some View {
        let now = Date()
        let minutesUntil = start.timeIntervalSince(now) / 60

        if let endDate, now >= start, now < endDate {
            Text("Now")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green)
                .clipShape(Capsule())
        } else if minutesUntil > 0, minutesUntil <= 15 {
            Text("In \(Int(minutesUntil)) min")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange)
                .clipShape(Capsule())
        } else {
            Text(formatTimeLabel(start))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func formatTimeLabel(_ date: Date) -> String {
        if action.isAllDay { return "All Day" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Preview View

struct CalendarActionPreviewView: View {
    let action: CalendarAction

    var body: some View {
        PreviewLayout(moduleName: "calendar") {
            PreviewHeader(
                title: action.title,
                subtitle: action.subtitle,
                systemIcon: action.iconName ?? "calendar",
                iconColor: previewColor
            )

            pills

            metadataRows
        }
    }

    @ViewBuilder
    private var pills: some View {
        HStack(spacing: 8) {
            if let start = action.startDate {
                PreviewPill(
                    text: statusText(for: start, endDate: action.endDate),
                    icon: "clock",
                    color: statusColor(
                        for: start,
                        endDate: action.endDate
                    )
                )
            }

            if let videoType = action.videoLinkType {
                PreviewPill(
                    text: videoLabel(for: videoType),
                    icon: "video.fill",
                    color: .blue
                )
            }

            if action.isAllDay {
                PreviewPill(
                    text: "All Day",
                    icon: "sun.max",
                    color: .orange
                )
            }
        }
    }

    @ViewBuilder
    private var metadataRows: some View {
        if let calendarName = action.calendarName {
            PreviewMetadataRow(
                icon: "calendar",
                label: "Calendar",
                value: calendarName
            )
        }

        if let start = action.startDate, !action.isAllDay {
            PreviewMetadataRow(
                icon: "clock",
                label: "Time",
                value: formatTimeRange(
                    start: start,
                    end: action.endDate
                )
            )
        }

        if let location = action.location, !location.isEmpty {
            PreviewMetadataRow(
                icon: "location",
                label: "Location",
                value: location
            )
        }

        if let attendees = action.attendeeNames, !attendees.isEmpty {
            PreviewMetadataRow(
                icon: "person.2",
                label: "Attendees",
                value: formatAttendees(attendees)
            )
        }

        if let videoURL = action.videoURL {
            PreviewMetadataRow(
                icon: "link",
                label: "Video Link",
                value: videoURL.host ?? videoURL.absoluteString,
                valueColor: .blue
            )
        }
    }

    private var previewColor: Color {
        switch action.calendarItemType {
        case .event:
            if let hex = action.calendarColorHex {
                return Color(calendarHex: hex)
            }
            return .blue
        case .utility:
            return .secondary
        }
    }

    private func statusText(
        for start: Date,
        endDate: Date?
    ) -> String {
        let now = Date()
        let minutesUntil = start.timeIntervalSince(now) / 60

        if let endDate, now >= start, now < endDate {
            return "Happening Now"
        } else if minutesUntil > 0, minutesUntil <= 60 {
            return "In \(Int(minutesUntil)) min"
        } else if minutesUntil > 60 {
            let hours = Int(minutesUntil / 60)
            let mins = Int(minutesUntil.truncatingRemainder(dividingBy: 60))
            if mins == 0 { return "In \(hours)h" }
            return "In \(hours)h \(mins)m"
        } else {
            return "Past"
        }
    }

    private func statusColor(
        for start: Date,
        endDate: Date?
    ) -> Color {
        let now = Date()
        let minutesUntil = start.timeIntervalSince(now) / 60

        if let endDate, now >= start, now < endDate { return .green }
        if minutesUntil > 0, minutesUntil <= 15 { return .orange }
        if minutesUntil <= 0 { return .secondary }
        return .blue
    }

    private func videoLabel(for type: VideoLinkType) -> String {
        switch type {
        case .zoom: return "Zoom"
        case .googleMeet: return "Google Meet"
        case .teams: return "Teams"
        }
    }

    private func formatTimeRange(start: Date, end: Date?) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let startStr = formatter.string(from: start)
        if let end {
            return "\(startStr) \u{2013} \(formatter.string(from: end))"
        }
        return startStr
    }

    private func formatAttendees(_ attendees: [String]) -> String {
        let shown = attendees.prefix(5).joined(separator: ", ")
        if attendees.count > 5 {
            return "\(shown) +\(attendees.count - 5) more"
        }
        return shown
    }
}

// MARK: - Color Extension

extension Color {
    init(calendarHex hex: String) {
        let cleaned = hex.trimmingCharacters(
            in: CharacterSet(charactersIn: "#")
        )
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
