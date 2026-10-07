import Foundation
import OSLog
import SwiftUI

/// Apple Notes through its scripting dictionary (see `NotesManager`): Search Notes (by
/// title or text), New Note, and the most recently edited notes as rows of the main search.
///
/// Listing takes a few Apple events and a large library's text a while, so notes are
/// cached and refreshed in the background. The main search never launches Notes or
/// brings up the Automation prompt: it refreshes only while Notes is running and
/// Vibeshed may script it. Search Notes, which the user asked for, waits for the first
/// listing and may do both.
actor NotesModule: ModuleConfigurable {
    let id = "notes"
    let displayName = "Notes"
    let iconName = "note.text"
    var isEnabled = true

    typealias Config = NotesConfig
    static var defaultConfig: Config? {
        .init()
    }

    var automationTargets: [String] {
        [NotesManager.bundleID]
    }

    static let notePrefix = "note."
    /// How old the cached listing gets before the next fetch refreshes it.
    static let refreshInterval: TimeInterval = 15

    private var config = NotesConfig()
    private let log = Log.module("notes")
    private var eventBus: EventBus?

    private var notes: [NoteInfo] = []
    /// Whether `notes` came from Notes at all, rather than being empty for want of a listing.
    private var hasListing = false
    private var listedAt = Date.distantPast
    private var listingError: Error?
    private var refreshTask: Task<Void, Never>?

    func initialize(context: ModuleContext) async throws {
        eventBus = context.eventBus
        refreshQuietlyIfStale()
        log.info("Notes module initialized")
    }

    func teardown() async {
        notes = []
        hasListing = false
        listedAt = .distantPast
    }

    func configDidUpdate(_ config: NotesConfig) async {
        if config.searchContent != self.config.searchContent {
            listedAt = .distantPast
        }
        self.config = config
    }

    static func validate(_ config: NotesConfig) -> ConfigValidationResult {
        var errors: [String] = []
        if config.maxResults < 0 {
            errors.append("maxResults must be non-negative")
        }
        if let folder = config.newNoteFolder, folder.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("newNoteFolder must not be empty")
        }
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    func provideActions(query _: String, scoring _: ScoringContext) async -> [any Action] {
        refreshQuietlyIfStale()
        let appIcon = NotesManager.appURL?.path
        let rows = Self.noteActions(notes, maxResults: config.maxResults, appIcon: appIcon)
        return Self.enabled(fixedActions(appIcon: appIcon) + rows, config: config)
    }

    /// Fixed actions and listed notes resolve without scripting, since keybindings are
    /// checked at config load. A note that isn't listed yet (Notes hasn't run since
    /// launch) resolves to an action that lists notes when it runs.
    func action(id: ActionID) async -> (any Action)? {
        guard id.moduleID == self.id else { return nil }
        let appIcon = NotesManager.appURL?.path
        if let action = fixedActions(appIcon: appIcon).first(where: { $0.id == id }) {
            return Self.enabled([action], config: config).first
        }
        guard id.actionName.hasPrefix(Self.notePrefix) else { return nil }
        let action = notes.first { Self.actionID(for: $0) == id }
            .map { Self.noteAction($0, relevance: 0.5, appIcon: appIcon) }
            ?? unlistedNoteAction(id: id, appIcon: appIcon)
        return Self.enabled([action], config: config).first
    }

    func provideParameterOptions(for parameterID: String, in _: ActionID, query: String) async -> [ParameterOption] {
        guard parameterID == "note" else { return [] }
        if hasListing {
            refreshQuietlyIfStale()
        } else {
            await refresh().value
        }
        if !hasListing, let listingError {
            return [Self.failureOption(listingError)]
        }
        return Self.searchOptions(notes, query: query, appURL: NotesManager.appURL)
    }

    /// `enabledActions` takes full names (`search`, `create`) or the `note` family.
    static func enabled(_ actions: [NotesAction], config: NotesConfig) -> [NotesAction] {
        guard let enabled = config.enabledActions else { return actions }
        return actions.filter { action in
            let name = action.id.actionName
            return enabled.contains(name) || enabled.contains(String(name.prefix { $0 != "." }))
        }
    }
}

// MARK: - Listing

extension NotesModule {
    private var isStale: Bool {
        Date().timeIntervalSince(listedAt) > Self.refreshInterval
    }

    /// Refreshes a stale listing in the background when that can neither launch Notes
    /// nor bring up the Automation prompt.
    private func refreshQuietlyIfStale() {
        guard isStale, refreshTask == nil, NotesManager.isRunning,
              AutomationConsent.status(for: NotesManager.bundleID) == .allowed
        else { return }
        refresh()
    }

    /// Lists notes unless a listing is already under way, and returns it to wait on.
    @discardableResult
    private func refresh() -> Task<Void, Never> {
        if let refreshTask {
            return refreshTask
        }
        let includeText = config.searchContent
        let task = Task { [self] in
            let start = ContinuousClock.now
            let result: Result<[NoteInfo], Error>
            do {
                result = try await .success(NotesManager.listNotes(includeText: includeText))
            } catch {
                result = .failure(error)
            }
            await finishRefresh(result, includedText: includeText, took: ContinuousClock.now - start)
        }
        refreshTask = task
        return task
    }

    private func finishRefresh(_ result: Result<[NoteInfo], Error>, includedText: Bool, took: Duration) async {
        refreshTask = nil
        // A listing started before `searchContent` changed is used, then replaced.
        listedAt = includedText == config.searchContent ? Date() : .distantPast
        switch result {
        case let .success(listed):
            let withText = listed.contains { $0.text != nil }
            log.debug(
                "Listed \(listed.count, privacy: .public) notes in \(took, privacy: .public), text: \(withText)"
            )
            hasListing = true
            listingError = nil
            guard listed != notes else { return }
            notes = listed
            await eventBus?.publish(.moduleActionsChanged(moduleID: id))
        case let .failure(error):
            listingError = error
            log.error("Failed to list notes: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Lists again on the next fetch, e.g. once a note was made.
    func markStale() {
        listedAt = .distantPast
    }

    /// The listing's error, for a Search Notes row chosen while Notes couldn't be read.
    func currentListingError() -> Error? {
        listingError
    }

    /// Opens the note behind a `note.` action ID, listing notes first when it isn't listed.
    func openNote(actionID: ActionID) async throws {
        if !notes.contains(where: { Self.actionID(for: $0) == actionID }) {
            await refresh().value
        }
        guard let note = notes.first(where: { Self.actionID(for: $0) == actionID }) else {
            throw listingError ?? NotesError.noteNotFound
        }
        try await NotesManager.show(noteID: note.id)
    }
}

// MARK: - Actions

extension NotesModule {
    func fixedActions(appIcon: String?) -> [NotesAction] {
        [searchAction(appIcon: appIcon), createAction(appIcon: appIcon)]
    }

    private func searchAction(appIcon: String?) -> NotesAction {
        NotesAction(
            id: ActionID(module: "notes", name: "search"),
            title: "Search Notes",
            subtitle: config.searchContent ? "Find a note by its title or text" : "Find a note by its title",
            iconName: "magnifyingglass",
            appIconPath: appIcon,
            relevanceScore: 0.88,
            keywords: ["notes", "note", "search", "find", "apple notes"],
            parameters: [
                ActionParameter(id: "note", label: "Note", type: .dynamicSelection(hint: "note"), isRequired: true),
            ]
        ) { [self] values in
            // The only row without an ID is the one saying Notes couldn't be read.
            guard let noteID = values["note"], !noteID.isEmpty else {
                throw await currentListingError() ?? NotesError.noteNotFound
            }
            try await NotesManager.show(noteID: noteID)
            return .dismiss
        }
    }

    private func createAction(appIcon: String?) -> NotesAction {
        let folder = config.newNoteFolder
        return NotesAction(
            id: ActionID(module: "notes", name: "create"),
            title: "New Note",
            subtitle: folder.map { "Start a note in \($0)" } ?? "Start a note in Notes",
            iconName: "square.and.pencil",
            appIconPath: appIcon,
            relevanceScore: 0.9,
            keywords: ["notes", "note", "new", "create", "write", "jot"],
            parameters: [
                ActionParameter(
                    id: "title",
                    label: "Title",
                    type: .text(placeholder: "Note title..."),
                    isRequired: true
                ),
            ]
        ) { [self] values in
            guard let title = values["title"]?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                return .showResult(title: "New Note", body: "Please enter a title for the note")
            }
            try await NotesManager.create(title: title, folder: folder)
            await markStale()
            return .dismiss
        }
    }

    private func unlistedNoteAction(id: ActionID, appIcon: String?) -> NotesAction {
        NotesAction(
            id: id,
            title: "Open Note",
            subtitle: "Notes",
            iconName: "note.text",
            appIconPath: appIcon,
            relevanceScore: 0.5
        ) { [self] _ in
            try await openNote(actionID: id)
            return .dismiss
        }
    }

    static func actionID(for note: NoteInfo) -> ActionID {
        ActionID(module: "notes", name: notePrefix + StableID.hash(note.id))
    }

    /// The `maxResults` most recently edited notes, most recent first.
    static func noteActions(_ notes: [NoteInfo], maxResults: Int, appIcon: String?) -> [NotesAction] {
        notes.prefix(max(0, maxResults)).enumerated().map { index, note in
            noteAction(note, relevance: max(0.4, 0.6 - Double(index) * 0.002), appIcon: appIcon)
        }
    }

    static func noteAction(_ note: NoteInfo, relevance: Double, appIcon: String?) -> NotesAction {
        let noteID = note.id
        return NotesAction(
            id: actionID(for: note),
            title: note.displayTitle,
            subtitle: note.folder,
            iconName: "note.text",
            appIconPath: appIcon,
            relevanceScore: relevance,
            keywords: titleKeywords(note.displayTitle) + [note.folder.lowercased()],
            note: note
        ) { _ in
            try await NotesManager.show(noteID: noteID)
            return .dismiss
        }
    }
}

// MARK: - Search Notes options

extension NotesModule {
    /// Every note, most recently edited first; the picker ranks them against the query.
    /// A note whose text contains the query and whose title doesn't shows the passage
    /// instead of its folder: the row then says why it matched, and the picker keeps it
    /// because the passage holds the query.
    static func searchOptions(_ notes: [NoteInfo], query: String, appURL: URL?) -> [ParameterOption] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let edited = Date.RelativeFormatStyle(presentation: .named)
        let now = Date()
        return notes.map { note in
            var subtitle = "\(note.folder) · \(min(note.modified, now).formatted(edited))"
            if !needle.isEmpty, note.title.range(of: needle, options: .caseInsensitive) == nil,
               let passage = note.text.flatMap({ passage(in: $0, around: needle) })
            {
                subtitle = passage
            }
            return ParameterOption(
                id: note.id,
                label: note.displayTitle,
                subtitle: subtitle,
                iconURL: appURL,
                keywords: titleKeywords(note.displayTitle) + [note.folder.lowercased()],
                makePreview: { AnyView(NotePreviewView(note: note)) }
            )
        }
    }

    /// The text around the first match of `needle`, on one line, starting just before
    /// it so a one-line row shows the match.
    static func passage(in text: String, around needle: String) -> String? {
        guard let match = text.range(of: needle, options: .caseInsensitive) else { return nil }
        let start = text.index(match.lowerBound, offsetBy: -24, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(match.upperBound, offsetBy: 96, limitedBy: text.endIndex) ?? text.endIndex
        var passage = text[start ..< end].split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if start > text.startIndex {
            passage = "…" + passage
        }
        if end < text.endIndex {
            passage += "…"
        }
        return passage
    }

    static func failureOption(_ error: Error) -> ParameterOption {
        ParameterOption(
            id: "",
            label: "Couldn't read your notes",
            subtitle: error.localizedDescription,
            iconName: "exclamationmark.triangle"
        )
    }
}
