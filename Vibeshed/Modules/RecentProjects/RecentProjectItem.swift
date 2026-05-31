import Foundation

/// Named accent used by recent-project list/preview views. Mapped to a SwiftUI
/// `Color` in the view layer so this model stays UI-framework-free and `Sendable`.
enum ProjectAccent: String, Sendable {
    case blue
    case purple
    case orange
    case green
    case cyan
    case red
    case secondary
}

/// A pill badge rendered in a recent-project preview.
struct ProjectPill: Sendable {
    let text: String
    let icon: String?
    let accent: ProjectAccent

    init(text: String, icon: String? = nil, accent: ProjectAccent = .secondary) {
        self.text = text
        self.icon = icon
        self.accent = accent
    }
}

/// A labelled metadata row rendered in a recent-project preview.
struct ProjectMetaRow: Sendable {
    let icon: String
    let label: String
    let value: String
    let selectable: Bool
}

/// A display-ready recent project / workspace produced by a `RecentProjectsProvider`.
///
/// The item carries everything the shared views need to render, plus an `open`
/// closure capturing whatever the provider needs to launch it (CLI path, full
/// project record, etc.) — mirroring the per-module `runner` closures it replaces.
struct RecentProjectItem: Sendable {
    /// Input used to derive a stable action ID (typically the project path).
    let stableInput: String
    let title: String
    let subtitle: String
    let isOpen: Bool

    /// Leading icon + accent, shared by the list row and the preview header.
    let listIcon: String
    let accent: ProjectAccent

    /// Optional trailing icon + label shown at the right edge of the list row.
    let trailingIcon: String?
    let trailingIconAccent: ProjectAccent
    let trailingLabel: String?

    let keywords: [String]
    let previewRows: [ProjectMetaRow]
    let previewPills: [ProjectPill]

    /// Launches the project. Called when the action is executed.
    let open: @Sendable () -> Void

    init(
        stableInput: String,
        title: String,
        subtitle: String,
        isOpen: Bool,
        listIcon: String,
        accent: ProjectAccent,
        trailingIcon: String? = nil,
        trailingIconAccent: ProjectAccent = .secondary,
        trailingLabel: String? = nil,
        keywords: [String] = [],
        previewRows: [ProjectMetaRow] = [],
        previewPills: [ProjectPill] = [],
        open: @escaping @Sendable () -> Void
    ) {
        self.stableInput = stableInput
        self.title = title
        self.subtitle = subtitle
        self.isOpen = isOpen
        self.listIcon = listIcon
        self.accent = accent
        self.trailingIcon = trailingIcon
        self.trailingIconAccent = trailingIconAccent
        self.trailingLabel = trailingLabel
        self.keywords = keywords
        self.previewRows = previewRows
        self.previewPills = previewPills
        self.open = open
    }
}
