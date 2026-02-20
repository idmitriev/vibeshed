import SwiftUI

// MARK: - Preview Header

struct PreviewHeader<Hero: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let hero: () -> Hero

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            hero()
                .frame(maxWidth: .infinity)

            Text(title)
                .font(.title3)
                .fontWeight(.medium)
                .lineLimit(2)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }
}

// MARK: - Preview Metadata Row

struct PreviewMetadataRow: View {
    let icon: String
    let label: String
    let value: String
    var valueColor: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 16)

            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()

            Text(value)
                .font(.caption)
                .foregroundStyle(valueColor)
        }
    }
}

// MARK: - Preview Module Badge

struct PreviewModuleBadge: View {
    let moduleName: String

    var body: some View {
        Text("Module: \(moduleName)")
            .font(.caption2)
            .foregroundStyle(.quaternary)
    }
}

// MARK: - Preview Layout

struct PreviewLayout<Content: View>: View {
    let moduleName: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                content()

                Spacer(minLength: 8)

                PreviewModuleBadge(moduleName: moduleName)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Preview Pill Badge

struct PreviewPill: View {
    let text: String
    var icon: String?
    var color: Color = .accentColor

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2)
            }
            Text(text)
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }
}
