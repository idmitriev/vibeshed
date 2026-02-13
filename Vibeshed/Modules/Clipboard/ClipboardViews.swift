import SwiftUI

struct ClipboardActionListItemView: View {
    let action: ClipboardAction

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.iconName ?? "doc.on.clipboard")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.body)
                    .lineLimit(1)

                if !action.subtitle.isEmpty {
                    Text(action.subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let timestamp = action.timestamp {
                Text(relativeTimeString(from: timestamp))
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct ClipboardActionPreviewView: View {
    let action: ClipboardAction

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: action.iconName ?? "doc.on.clipboard")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .frame(width: 64, height: 64)

            Text(action.title)
                .font(.title2)

            if let preview = action.contentPreview {
                ScrollView {
                    Text(preview)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .frame(maxHeight: 200)
            }

            HStack(spacing: 16) {
                if let contentType = action.contentType {
                    Label(
                        contentType.rawValue.capitalized,
                        systemImage: iconForContentType(contentType)
                    )
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
                if let timestamp = action.timestamp {
                    Label(relativeTimeString(from: timestamp), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Text("Module: clipboard")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Helpers

private func relativeTimeString(from date: Date) -> String {
    let elapsed = Date().timeIntervalSince(date)
    switch elapsed {
    case ..<10: return "just now"
    case ..<60: return "\(Int(elapsed))s ago"
    case ..<3600: return "\(Int(elapsed / 60))m ago"
    case ..<86400: return "\(Int(elapsed / 3600))h ago"
    case ..<172_800: return "yesterday"
    default:
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}

private func iconForContentType(_ type: ClipboardContentType) -> String {
    switch type {
    case .text: "doc.plaintext"
    case .url: "link"
    case .filePath: "folder"
    }
}
