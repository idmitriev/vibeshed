import SwiftUI

struct MenuActionPreviewView: View {
    let action: MenuAction

    var body: some View {
        PreviewLayout(moduleName: "menu") {
            PreviewHeader(title: action.title, subtitle: action.subtitle) {
                Group {
                    if let path = action.appIconPath {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: action.iconName ?? "filemenu.and.selection")
                            .font(.system(size: 56))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 72, height: 72)
            }

            VStack(alignment: .leading, spacing: 8) {
                if let appName = action.appName {
                    PreviewMetadataRow(icon: "app", label: "Application", value: appName)
                }
                if let entry = action.entry {
                    PreviewMetadataRow(icon: "filemenu.and.selection", label: "Menu", value: entry.location)
                    if let shortcut = entry.shortcut {
                        PreviewMetadataRow(icon: "command", label: "Shortcut", value: shortcut)
                    }
                }
            }

            if action.entry?.isChecked == true {
                PreviewPill(text: "On", icon: "checkmark", color: .green)
            }
        }
    }
}
