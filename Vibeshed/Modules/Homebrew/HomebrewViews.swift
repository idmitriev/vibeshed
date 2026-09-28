import SwiftUI

struct HomebrewActionListItemView: View {
    let action: HomebrewAction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.iconName ?? "cup.and.saucer")
                .font(.title3)
                .foregroundStyle(.secondary)
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
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

struct HomebrewActionPreviewView: View {
    let action: HomebrewAction

    var body: some View {
        PreviewLayout(moduleName: "homebrew") {
            PreviewHeader(
                title: action.title,
                subtitle: action.subtitle,
                systemIcon: action.iconName ?? "cup.and.saucer"
            )
        }
    }
}

/// Preview for a formula or cask highlighted in the install and uninstall pickers.
/// Sections run most to least important, since long ones don't fit the panel.
struct HomebrewPackagePreview: View {
    let package: HomebrewPackage

    var body: some View {
        PreviewLayout(moduleName: "homebrew") {
            PreviewHeader(title: package.displayName, subtitle: package.description ?? "") {
                hero
            }

            if !badges.isEmpty {
                PreviewFlowLayout(spacing: 6) {
                    ForEach(badges) { badge in
                        PreviewPill(text: badge.text, icon: badge.icon, color: badge.color)
                    }
                }
            }

            if !warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(warnings) { warning in
                        Label(warning.text, systemImage: warning.icon)
                            .font(.caption)
                            .foregroundStyle(warning.color)
                    }
                }
            }

            if !details.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(details) { detail in
                        PreviewMetadataRow(icon: detail.icon, label: detail.text, value: detail.value)
                    }
                }
            }

            if let caveats = package.caveats {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Caveats")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(caveats)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }
        }
    }

    @ViewBuilder
    private var hero: some View {
        if let appPath = package.existingAppPath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: appPath))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
        } else {
            Image(systemName: package.isCask ? "app" : "shippingbox")
                .font(.system(size: 56))
                .foregroundStyle(.primary.opacity(0.5))
                .frame(width: 72, height: 72)
        }
    }

    // MARK: - Content

    private struct Item: Identifiable {
        let icon: String
        let text: String
        var value = ""
        var color: Color = .secondary

        var id: String {
            text
        }
    }

    private var badges: [Item] {
        var badges: [Item] = []
        if package.isInstalled {
            let text = package.isInstalledAsDependency ? "Installed as dependency" : "Installed"
            badges.append(Item(icon: "checkmark.circle.fill", text: text, color: .green))
        }
        if package.isOutdated {
            badges.append(Item(icon: "arrow.up.circle.fill", text: "Update available", color: .orange))
        }
        if package.isPinned {
            badges.append(Item(icon: "pin.fill", text: "Pinned"))
        }
        if package.autoUpdates {
            badges.append(Item(icon: "arrow.triangle.2.circlepath", text: "Auto-updates"))
        }
        if package.isKegOnly {
            badges.append(Item(icon: "lock", text: "Keg-only"))
        }
        return badges
    }

    private var warnings: [Item] {
        var warnings: [Item] = []
        if let notice = package.disabling {
            warnings.append(Item(icon: "xmark.octagon.fill", text: Self.describe("Disabled", notice), color: .red))
        } else if let notice = package.deprecation {
            warnings.append(Item(
                icon: "exclamationmark.triangle.fill",
                text: Self.describe("Deprecated", notice),
                color: .orange
            ))
        }
        // brew refuses to install over an app it didn't put there.
        if package.isCask, !package.isInstalled, let appPath = package.existingAppPath {
            let url = URL(fileURLWithPath: appPath)
            warnings.append(Item(
                icon: "exclamationmark.triangle.fill",
                text: "\(url.lastPathComponent) is already in \(url.deletingLastPathComponent().path)",
                color: .orange
            ))
        }
        return warnings
    }

    private var details: [Item] {
        var details: [Item] = []
        if let version = Self.versionText(package) {
            details.append(Item(icon: "tag", text: "Version", value: version))
        }
        if let homepage = package.homepage {
            details.append(Item(icon: "globe", text: "Homepage", value: Self.displayURL(homepage)))
        }
        if let license = package.license {
            details.append(Item(icon: "checkmark.seal", text: "License", value: license))
        }
        let apps = package.appPaths.map { URL(fileURLWithPath: $0).lastPathComponent }
        if !apps.isEmpty {
            details.append(Item(icon: "app", text: "App", value: apps.joined(separator: ", ")))
        }
        let lists = [
            ("point.3.connected.trianglepath.dotted", "Dependencies", package.dependencies),
            ("arrow.turn.left.up", "Required by", package.requiredBy),
            ("xmark.circle", "Conflicts with", package.conflicts),
        ]
        for (icon, text, names) in lists where !names.isEmpty {
            details.append(Item(icon: icon, text: text, value: names.joined(separator: ", ")))
        }
        if let tap = package.tap, !["homebrew/core", "homebrew/cask"].contains(tap) {
            details.append(Item(icon: "square.stack.3d.up", text: "Tap", value: tap))
        }
        return details
    }

    // MARK: - Formatting

    /// The latest version, with the installed one in front when it's behind.
    nonisolated static func versionText(_ package: HomebrewPackage) -> String? {
        guard let latest = package.version else { return package.installedVersion }
        guard package.isOutdated, let installed = package.installedVersion, installed != latest else {
            return shortVersion(latest)
        }
        let (from, to) = (shortVersion(installed), shortVersion(latest))
        return from == to ? "\(installed) → \(latest)" : "\(from) → \(to)"
    }

    /// Casks can append a build to the version ("2.110.0,dfb2ba6…"), too long to be worth showing.
    private nonisolated static func shortVersion(_ version: String) -> String {
        String(version.prefix { $0 != "," })
    }

    /// `https://www.mozilla.org/firefox/` → `mozilla.org/firefox`.
    nonisolated static func displayURL(_ url: String) -> String {
        var text = Substring(url)
        for prefix in ["https://", "http://", "www."] where text.hasPrefix(prefix) {
            text = text.dropFirst(prefix.count)
        }
        return String(text.hasSuffix("/") ? text.dropLast() : text)
    }

    /// "Deprecated: discontinued, replaced by chatgpt".
    nonisolated static func describe(_ status: String, _ notice: HomebrewPackage.Notice) -> String {
        var text = status
        if let reason = notice.reason {
            text += ": " + reason.replacingOccurrences(of: "_", with: " ")
        }
        if let replacement = notice.replacement {
            text += ", replaced by \(replacement)"
        }
        return text
    }
}
