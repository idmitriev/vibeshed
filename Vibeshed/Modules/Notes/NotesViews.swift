import SwiftUI

/// A note's title, folder, last edit and the start of its text.
struct NotePreviewView: View {
    let note: NoteInfo

    var body: some View {
        PreviewLayout(moduleName: "notes") {
            PreviewHeader(title: note.displayTitle, subtitle: note.folder) {
                hero
            }

            PreviewMetadataRow(
                icon: "clock",
                label: "Edited",
                value: note.modified.formatted(date: .abbreviated, time: .shortened)
            )

            if let body = note.bodyText {
                Divider()
                // Only the start: a long note's text would take a while to lay out.
                Text(String(body.prefix(1200)))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(14)
            }
        }
    }

    @ViewBuilder
    private var hero: some View {
        if let url = NotesManager.appURL {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 56, height: 56)
        } else {
            Image(systemName: "note.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .frame(width: 56, height: 56)
        }
    }
}
