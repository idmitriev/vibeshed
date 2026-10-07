import AppKit
import Foundation

/// A note in Notes.app, as its scripting dictionary describes it.
struct NoteInfo: Sendable, Equatable {
    /// Notes' Core Data URI (`x-coredata://…/ICNote/p123`), stable for the note's lifetime.
    let id: String
    /// The note's first line; empty for a note with no text yet.
    let title: String
    let folder: String
    let modified: Date
    /// The whole note as plain text, title line included; nil unless content search is on.
    let text: String?

    /// The name Notes shows for the note.
    var displayTitle: String {
        title.isEmpty ? "New Note" : title
    }

    /// The text after the title line.
    var bodyText: String? {
        guard let text else { return nil }
        let body = text.drop { !$0.isNewline }.drop(while: \.isWhitespace)
        return body.isEmpty ? nil : String(body)
    }
}

enum NotesError: Error, LocalizedError, Equatable {
    case unreadableListing
    case noteNotFound
    case folderNotFound(String)
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .unreadableListing: "Notes changed while it was being read; try again"
        case .noteNotFound: "That note is no longer in Notes"
        case let .folderNotFound(name): "Notes has no folder named \"\(name)\" (newNoteFolder)"
        case .notAuthorized:
            "Vibeshed may not control Notes: allow it in System Settings › Privacy & Security › Automation"
        }
    }
}

/// Drives Notes.app through its scripting dictionary: lists notes, shows one, makes one.
///
/// The scripts are JavaScript for Automation, not AppleScript. On macOS 27, osascript
/// running the AppleScript listing crashed (SIGBUS/SIGSEGV in AppleScript's
/// `ASScriptError`) on about half the runs against a real library, printing nothing,
/// while the same script never failed in-process and the JXA one never failed through
/// osascript.
enum NotesManager {
    static let bundleID = "com.apple.Notes"

    static var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    /// Every note but those in Recently Deleted, most recently edited first. Launches
    /// Notes when it isn't running.
    static func listNotes(includeText: Bool) async throws -> [NoteInfo] {
        // Generous timeout: Notes may be launching, and a large library's text takes a while.
        let output = try await run(listScript(includeText: includeText), timeout: 30)
        return try parseListing(Data(output.utf8), excludingFolders: trashFolderNames)
    }

    /// Opens the note in Notes' main window and brings Notes to the front.
    static func show(noteID: String) async throws {
        try await run(showScript(noteID: noteID), timeout: 15, missing: .noteNotFound)
    }

    /// Makes a note whose first line is `title` in `folder` (nil = the default folder of
    /// the default account) and opens it.
    static func create(title: String, folder: String?) async throws {
        let script = createScript(title: title, folder: folder)
        try await run(script, timeout: 15, missing: folder.map(NotesError.folderNotFound))
    }

    /// Runs a `script` and returns its JSON. Turns the failures the user can do something
    /// about into errors that say what: Automation turned off (-1743), and `missing` for
    /// an object Notes doesn't have (-1728).
    @discardableResult
    private static func run(_ script: String, timeout: TimeInterval, missing: NotesError? = nil) async throws
        -> String
    {
        let output: String
        do {
            output = try await AppleScriptRunner.run(script, language: .javaScript, timeout: timeout)
        } catch let AppleScriptError.scriptFailed(message) {
            throw scriptError(code: errorCode(in: message), message: message, missing: missing)
        }
        if let failure = scriptFailure(in: output) {
            throw scriptError(code: failure.number, message: failure.message, missing: missing)
        }
        return output
    }

    static func scriptError(code: Int?, message: String, missing: NotesError?) -> Error {
        if code == -1743 {
            return NotesError.notAuthorized
        }
        if code == -1728, let missing {
            return missing
        }
        return AppleScriptError.scriptFailed(code.map { "\(message) (\($0))" } ?? message)
    }

    /// The number osascript ends an error message with: "… (-1743)".
    static func errorCode(in message: String) -> Int? {
        guard message.hasSuffix(")"), let open = message.lastIndex(of: "(") else { return nil }
        return Int(message[message.index(after: open) ..< message.index(before: message.endIndex)])
    }

    struct ScriptFailure: Decodable, Equatable {
        let number: Int?
        let message: String
    }

    /// The error a `script` returned instead of its result.
    static func scriptFailure(in output: String) -> ScriptFailure? {
        struct Reply: Decodable {
            let error: ScriptFailure
        }
        guard output.hasPrefix(#"{"error":"#) else { return nil }
        return try? JSONDecoder().decode(Reply.self, from: Data(output.utf8)).error
    }

    // MARK: - Recently Deleted

    /// Scripting lists the notes in Recently Deleted like any folder's, under the name
    /// Notes shows: its translation for the language Notes runs in, read from Notes'
    /// framework once, plus the English name in case that file moves. Not every
    /// translation, so a folder of the user's that shares another language's name stays.
    static let trashFolderNames: Set<String> = {
        let table = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/NotesShared.framework/Resources")
            .appendingPathComponent("Localizable.loctable")
        let languages = (try? Data(contentsOf: table))
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
        return trashFolderNames(in: languages ?? [:], preferences: Locale.preferredLanguages)
    }()

    /// "Recently Deleted" in the localization of `languages` (a loctable: language →
    /// key → string) that a bundle offering them would pick for `preferences`.
    static func trashFolderNames(in languages: [String: Any], preferences: [String]) -> Set<String> {
        var names: Set<String> = ["Recently Deleted"]
        let chosen = Bundle.preferredLocalizations(from: Array(languages.keys), forPreferences: preferences)
        for language in chosen {
            if let name = (languages[language] as? [String: Any])?["Recently Deleted"] as? String {
                names.insert(name)
            }
        }
        return names
    }

    // MARK: - Scripts

    /// The most folders a listing walks, against a folder tree scripting reports in a loop.
    static let maxFolders = 1000

    /// A JXA script whose `run` does `body` with `Notes` bound to the app and returns its
    /// JSON, or the error as `{"error": {"number", "message"}}`, so it arrives on stdout
    /// rather than as osascript's message on stderr.
    static func script(_ body: [String]) -> String {
        ([
            "function run() {",
            "const Notes = Application(\(jsString(bundleID)));",
            "try {",
        ] + body + [
            "} catch (error) {",
            "const number = error.errorNumber === undefined ? null : error.errorNumber;",
            "return JSON.stringify({ error: { number: number, message: String(error.message) } });",
            "}",
            "}",
        ]).joined(separator: "\n")
    }

    /// Note IDs, titles, edit times (seconds since 1970) and, with `includeText`, plain
    /// text, one Apple event each, then each folder's name and note IDs. A failure to
    /// read the text (a locked note, say) leaves it out rather than failing the listing.
    ///
    /// Folders come from walking them: a note's `container` gives references scripting
    /// can't use. The walk goes breadth first through subfolders, so a note in a
    /// subfolder is listed under it last.
    static func listScript(includeText: Bool) -> String {
        var body = [
            "const notes = Notes.notes;",
            "const listing = {",
            "ids: notes.id(),",
            "titles: notes.name(),",
            "modified: notes.modificationDate().map(date => date ? date.getTime() / 1000 : 0),",
            "folders: []",
            "};",
        ]
        if includeText {
            body.append("try { listing.texts = notes.plaintext(); } catch (error) {}")
        }
        body += [
            "const queue = Notes.folders();",
            "for (let i = 0; i < queue.length && i < \(maxFolders); i++) {",
            "listing.folders.push({ name: queue[i].name(), notes: queue[i].notes.id() });",
            "queue.push(...queue[i].folders());",
            "}",
            "return JSON.stringify(listing);",
        ]
        return script(body)
    }

    static func showScript(noteID: String) -> String {
        script([
            "Notes.show(Notes.notes.byId(\(jsString(noteID))));",
            "Notes.activate();",
            "return \"{}\";",
        ])
    }

    static func createScript(title: String, folder: String?) -> String {
        let location = folder.map { "Notes.folders.byName(\(jsString($0)))" } ?? "Notes.defaultAccount.defaultFolder"
        return script([
            "const note = Notes.Note({ body: \(jsString(noteBody(title: title))) });",
            "\(location).notes.push(note);",
            "Notes.show(note);",
            "Notes.activate();",
            "return \"{}\";",
        ])
    }

    /// The HTML Notes reads a new note's body from: the title in Notes' Title style,
    /// or one empty line.
    static func noteBody(title: String) -> String {
        guard !title.isEmpty else { return "<div><br></div>" }
        let escaped = title
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return "<h1>\(escaped)</h1>"
    }

    /// `string` as a JavaScript string literal.
    static func jsString(_ string: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return (try? encoder.encode(string)).flatMap { String(bytes: $0, encoding: .utf8) } ?? "\"\""
    }

    // MARK: - Parsing

    /// `listScript`'s JSON. Notes reports `missing value` (null) for a property it has
    /// no value for.
    struct Listing: Decodable {
        let ids: [String?]
        let titles: [String?]
        let modified: [Double?]
        let texts: [String?]?
        let folders: [ListedFolder]
    }

    struct ListedFolder: Decodable {
        let name: String?
        let notes: [String?]
    }

    /// Reads `listScript`'s output. Lists of different lengths mean a note came or went
    /// between two of its Apple events, so nothing would line up. A note no folder lists
    /// (one made mid-listing) has no folder name.
    static func parseListing(_ data: Data, excludingFolders excluded: Set<String>) throws -> [NoteInfo] {
        guard let listing = try? JSONDecoder().decode(Listing.self, from: data),
              listing.titles.count == listing.ids.count, listing.modified.count == listing.ids.count
        else { throw NotesError.unreadableListing }
        let texts = listing.texts?.count == listing.ids.count ? listing.texts : nil

        // The last folder listing a note is the deepest, should a folder's notes include
        // its subfolders'.
        var folders: [String: String] = [:]
        for folder in listing.folders {
            for case let noteID? in folder.notes {
                folders[noteID] = folder.name ?? ""
            }
        }

        var notes: [NoteInfo] = []
        for (index, noteID) in listing.ids.enumerated() {
            guard let noteID, !noteID.isEmpty else { continue }
            let folder = folders[noteID] ?? ""
            guard !excluded.contains(folder) else { continue }
            notes.append(NoteInfo(
                id: noteID,
                title: listing.titles[index] ?? "",
                folder: folder,
                modified: Date(timeIntervalSince1970: listing.modified[index] ?? 0),
                text: texts.map { $0[index] ?? "" }
            ))
        }
        return notes.sorted { $0.modified > $1.modified }
    }
}
