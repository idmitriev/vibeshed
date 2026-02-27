import SwiftUI

// MARK: - List Item View

struct MeetingPrepListItemView: View {
    let action: MeetingPrepAction

    var body: some View {
        HStack(spacing: 12) {
            actionIcon
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

            if let start = action.startDate {
                timeBadge(for: start, endDate: action.endDate)
            }

            if action.videoURL != nil {
                Image(systemName: "video.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var actionIcon: some View {
        switch action.actionType {
        case .prepForMeeting:
            ZStack {
                Circle()
                    .fill(calendarColor.opacity(0.2))
                    .frame(width: 28, height: 28)
                Image(systemName: "clock.badge.checkmark")
                    .font(.caption)
                    .foregroundStyle(calendarColor)
            }
        case .joinVideo:
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 28, height: 28)
                Image(systemName: "video.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        case .hideDistractions:
            Image(systemName: "eye.slash")
                .font(.title3)
                .foregroundStyle(.orange)
        case .restoreWindows:
            Image(systemName: "macwindow.on.rectangle")
                .font(.title3)
                .foregroundStyle(.green)
        case .utility:
            Image(systemName: action.iconName ?? "gear")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var calendarColor: Color {
        if let hex = action.calendarColorHex {
            return Color(calendarHex: hex)
        }
        return .purple
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
            Text("In \(Int(minutesUntil))m")
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
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Preview View

struct MeetingPrepPreviewView: View {
    let action: MeetingPrepAction

    var body: some View {
        PreviewLayout(moduleName: "meetingPrep") {
            PreviewHeader(
                title: action.title,
                subtitle: action.subtitle,
                systemIcon: action.iconName ?? "clock.badge.checkmark",
                iconColor: previewColor
            )

            pills

            metadataRows

            if action.actionType == .prepForMeeting {
                prepDescription
            }
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

            PreviewPill(
                text: actionTypeLabel,
                icon: actionTypeIcon,
                color: previewColor
            )
        }
    }

    @ViewBuilder
    private var metadataRows: some View {
        if let meetingTitle = action.meetingTitle,
           action.actionType != .prepForMeeting
        {
            PreviewMetadataRow(
                icon: "calendar",
                label: "Meeting",
                value: meetingTitle
            )
        }

        if let calendarName = action.calendarName {
            PreviewMetadataRow(
                icon: "calendar",
                label: "Calendar",
                value: calendarName
            )
        }

        if let start = action.startDate {
            PreviewMetadataRow(
                icon: "clock",
                label: "Time",
                value: formatTimeRange(
                    start: start,
                    end: action.endDate
                )
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

    @ViewBuilder
    private var prepDescription: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("This action will:")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            descriptionBullet(
                icon: "eye.slash",
                text: "Minimize distracting app windows"
            )

            if action.videoURL != nil {
                descriptionBullet(
                    icon: "video.fill",
                    text: "Join video call"
                )
            }

            descriptionBullet(
                icon: "macwindow.on.rectangle",
                text: "Offer to restore windows after"
            )
        }
    }

    private func descriptionBullet(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var previewColor: Color {
        switch action.actionType {
        case .prepForMeeting:
            if let hex = action.calendarColorHex {
                return Color(calendarHex: hex)
            }
            return .purple
        case .joinVideo:
            return .blue
        case .hideDistractions:
            return .orange
        case .restoreWindows:
            return .green
        case .utility:
            return .secondary
        }
    }

    private var actionTypeLabel: String {
        switch action.actionType {
        case .prepForMeeting: return "Prep"
        case .joinVideo: return "Join"
        case .hideDistractions: return "Focus"
        case .restoreWindows: return "Restore"
        case .utility: return "Utility"
        }
    }

    private var actionTypeIcon: String {
        switch action.actionType {
        case .prepForMeeting: return "clock.badge.checkmark"
        case .joinVideo: return "video.fill"
        case .hideDistractions: return "eye.slash"
        case .restoreWindows: return "macwindow.on.rectangle"
        case .utility: return "gear"
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
            let mins = Int(
                minutesUntil.truncatingRemainder(dividingBy: 60)
            )
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
