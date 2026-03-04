import SwiftUI

// MARK: - List Item View

struct TimerActionListItemView: View {
    let action: TimerAction

    var body: some View {
        HStack(spacing: 12) {
            timerIcon
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

            if action.isActive, let fireDate = action.fireDate {
                countdownBadge(for: fireDate)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var timerIcon: some View {
        switch action.timerItemType {
        case .timer where action.isActive:
            ZStack {
                Circle()
                    .stroke(progressColor.opacity(0.2), lineWidth: 3)
                    .frame(width: 28, height: 28)
                Circle()
                    .trim(
                        from: 0,
                        to: CGFloat(progress)
                    )
                    .stroke(
                        progressColor,
                        style: StrokeStyle(
                            lineWidth: 3,
                            lineCap: .round
                        )
                    )
                    .frame(width: 28, height: 28)
                    .rotationEffect(.degrees(-90))
                Image(systemName: "timer")
                    .font(.system(size: 10))
                    .foregroundStyle(progressColor)
            }
        case .reminder where action.isActive:
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 28, height: 28)
                Image(systemName: "bell.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.blue)
            }
        default:
            Image(
                systemName: action.iconName ?? "timer"
            )
            .font(.title3)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func countdownBadge(for fireDate: Date) -> some View {
        let remaining = fireDate.timeIntervalSince(Date())

        if remaining > 0 {
            Text(
                TimerParser.formatCountdown(remaining)
            )
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(progressColor)
            .clipShape(Capsule())
        } else {
            Text("Done")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green)
                .clipShape(Capsule())
        }
    }

    private var progress: Double {
        guard let fireDate = action.fireDate,
              let duration = action.originalDuration,
              duration > 0
        else {
            return 0
        }
        let remaining = fireDate.timeIntervalSince(Date())
        return max(0, min(1, remaining / duration))
    }

    private var progressColor: Color {
        let p = progress
        if p > 0.5 { return .green }
        if p > 0.1 { return .orange }
        return .red
    }
}

// MARK: - Preview View

struct TimerActionPreviewView: View {
    let action: TimerAction

    var body: some View {
        PreviewLayout(moduleName: "timer") {
            PreviewHeader(
                title: action.title,
                subtitle: action.subtitle,
                systemIcon: action.iconName ?? "timer",
                iconColor: headerColor
            )

            pills

            metadataRows
        }
    }

    @ViewBuilder
    private var pills: some View {
        HStack(spacing: 8) {
            if action.isActive {
                PreviewPill(
                    text: "Active",
                    icon: "circle.fill",
                    color: .green
                )
            }

            switch action.timerItemType {
            case .timer:
                PreviewPill(
                    text: "Timer",
                    icon: "timer",
                    color: .orange
                )
            case .reminder:
                PreviewPill(
                    text: "Reminder",
                    icon: "bell",
                    color: .blue
                )
            case .utility:
                EmptyView()
            }

            if action.isActive, let fireDate = action.fireDate {
                let remaining = fireDate.timeIntervalSince(Date())
                if remaining > 0 {
                    PreviewPill(
                        text: TimerParser.formatCountdown(
                            remaining
                        ),
                        icon: "clock",
                        color: countdownColor(remaining: remaining)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var metadataRows: some View {
        if let fireDate = action.fireDate {
            PreviewMetadataRow(
                icon: "clock",
                label: "Fires at",
                value: formatDateTime(fireDate)
            )
        }

        if let created = action.createdDate {
            PreviewMetadataRow(
                icon: "calendar",
                label: "Created",
                value: formatDateTime(created)
            )
        }

        if let duration = action.originalDuration {
            PreviewMetadataRow(
                icon: "hourglass",
                label: "Duration",
                value: TimerParser.formatDurationLong(duration)
            )
        }

        if let label = action.label, !label.isEmpty {
            PreviewMetadataRow(
                icon: "tag",
                label: "Label",
                value: label
            )
        }

        if action.isActive {
            PreviewMetadataRow(
                icon: "hand.tap",
                label: "Action",
                value: "Click to cancel"
            )
        }
    }

    private var headerColor: Color {
        switch action.timerItemType {
        case .timer: .orange
        case .reminder: .blue
        case .utility: .secondary
        }
    }

    private func countdownColor(remaining: TimeInterval) -> Color {
        guard let duration = action.originalDuration, duration > 0
        else { return .blue }
        let fraction = remaining / duration
        if fraction > 0.5 { return .green }
        if fraction > 0.1 { return .orange }
        return .red
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "h:mm:ss a"
        } else if calendar.isDateInTomorrow(date) {
            formatter.dateFormat = "'Tomorrow' h:mm a"
        } else {
            formatter.dateFormat = "MMM d, h:mm a"
        }
        return formatter.string(from: date)
    }
}
