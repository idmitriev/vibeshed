import SwiftUI

// MARK: - Preview Header

struct PreviewHeader<Hero: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let hero: () -> Hero

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            hero()

            Text(title)
                .font(.title3)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        }
    }
}

extension PreviewHeader where Hero == AnyView {
    init(
        title: String,
        subtitle: String,
        systemIcon: String,
        iconColor: Color = .secondary
    ) {
        self.title = title
        self.subtitle = subtitle
        self.hero = {
            AnyView(
                Image(systemName: systemIcon)
                    .font(.system(size: 56))
                    .foregroundStyle(iconColor)
                    .frame(width: 72, height: 72)
            )
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
                .frame(width: 18)

            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

// MARK: - Preview Module Badge

struct PreviewModuleBadge: View {
    let moduleName: String

    var body: some View {
        Text("Module: \(moduleName)")
            .font(.caption)
            .foregroundStyle(.quaternary)
    }
}

// MARK: - Preview Layout

struct PreviewLayout<Content: View>: View {
    let moduleName: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content()

            Spacer(minLength: 0)

            PreviewModuleBadge(moduleName: moduleName)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
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
                    .font(.caption)
            }
            Text(text)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }
}
