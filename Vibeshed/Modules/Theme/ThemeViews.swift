import SwiftUI

struct ThemeActionListItemView: View {
    let action: ThemeAction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.iconName ?? "paintpalette")
                .font(.title3)
                .foregroundStyle(iconColor)
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

            if let badge = categoryBadge {
                Text(badge)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var iconColor: Color {
        switch action.category {
        case .system: return .orange
        case .vscode: return .blue
        case .jetbrains: return .purple
        case .iterm: return .green
        case .github: return .gray
        case .preset: return .pink
        case .none: return .secondary
        }
    }

    private var categoryBadge: String? {
        switch action.category {
        case .vscode: return "VS Code"
        case .jetbrains: return "JetBrains"
        case .iterm: return "iTerm"
        case .github: return "GitHub"
        case .preset: return "Preset"
        case .system, .none: return nil
        }
    }
}

struct ThemeActionPreviewView: View {
    let action: ThemeAction

    var body: some View {
        PreviewLayout(moduleName: "theme") {
            PreviewHeader(
                title: action.title,
                subtitle: action.subtitle,
                systemIcon: action.iconName ?? "paintpalette"
            )

            if case .preset(let preset) = action.category {
                presetDetails(preset)
            }
        }
    }

    @ViewBuilder
    private func presetDetails(_ preset: ThemePreset) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Changes")
                .font(.headline)
                .padding(.top, 4)

            if let appearance = preset.appearance {
                PreviewMetadataRow(
                    icon: appearance == "dark" ? "moon.fill" : "sun.max.fill",
                    label: "Appearance",
                    value: appearance.capitalized
                )
            }
            if let accent = preset.accentColor {
                PreviewMetadataRow(
                    icon: "paintpalette.fill",
                    label: "Accent Color",
                    value: accent
                )
            }
            if let vscode = preset.vscodeTheme {
                PreviewMetadataRow(
                    icon: "chevron.left.forwardslash.chevron.right",
                    label: "VS Code",
                    value: vscode
                )
            }
            if let jb = preset.jetbrainsTheme {
                PreviewMetadataRow(
                    icon: "hammer.fill",
                    label: "JetBrains",
                    value: jb
                )
            }
            if let iterm = preset.itermPreset {
                PreviewMetadataRow(
                    icon: "terminal.fill",
                    label: "iTerm",
                    value: iterm
                )
            }
            if let github = preset.githubTheme {
                PreviewMetadataRow(
                    icon: "globe",
                    label: "GitHub",
                    value: github.capitalized
                )
            }
            if let wallpaper = preset.wallpaper {
                PreviewMetadataRow(
                    icon: "photo.fill",
                    label: "Wallpaper",
                    value: (wallpaper as NSString).lastPathComponent
                )
            }
        }
    }
}
