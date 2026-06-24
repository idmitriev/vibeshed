import SwiftUI

struct ZoomActionListItemView: View {
    let action: ZoomAction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.iconName ?? iconForType)
                .font(.title3)
                .foregroundStyle(colorForType)
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

            Text(typeLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var iconForType: String {
        switch action.zoomItemType {
        case .meeting: "video.fill"
        case .utility: "video"
        }
    }

    private var colorForType: Color {
        switch action.zoomItemType {
        case .meeting: .blue
        case .utility: .secondary
        }
    }

    private var typeLabel: String {
        switch action.zoomItemType {
        case .meeting: "Meeting"
        case .utility: "Zoom"
        }
    }
}

struct ZoomActionPreviewView: View {
    let action: ZoomAction

    var body: some View {
        PreviewLayout(moduleName: "zoom") {
            PreviewHeader(
                title: action.title,
                subtitle: action.subtitle,
                systemIcon: action.iconName ?? "video.fill",
                iconColor: previewColor
            )

            PreviewPill(
                text: pillText,
                icon: pillIcon,
                color: previewColor
            )

            if let meetingId = action.meetingId, !meetingId.isEmpty {
                PreviewMetadataRow(
                    icon: "number",
                    label: "Meeting ID",
                    value: ZoomManager.formatMeetingId(meetingId)
                )
            }
        }
    }

    private var previewColor: Color {
        switch action.zoomItemType {
        case .meeting: .blue
        case .utility: .secondary
        }
    }

    private var pillText: String {
        switch action.zoomItemType {
        case .meeting: "Meeting"
        case .utility: "Zoom"
        }
    }

    private var pillIcon: String {
        switch action.zoomItemType {
        case .meeting: "video.fill"
        case .utility: "video"
        }
    }
}
