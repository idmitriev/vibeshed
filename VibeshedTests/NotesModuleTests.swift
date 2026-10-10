@testable import Vibeshed
import XCTest

/// Covers the notes module without Notes: the listing's parsing, the scripts it sends,
/// config, action IDs, and Search Notes' options.
final class NotesManagerTests: XCTestCase {
    /// `listScript`'s output.
    private func listing(
        ids: [String?], titles: [String?], modified: [Double?],
        folders: [(name: String, noteIDs: [String])], texts: [String?]? = nil
    ) throws -> Data {
        var object: [String: Any] = [
            "ids": ids.map { $0 ?? NSNull() as Any },
            "titles": titles.map { $0 ?? NSNull() as Any },
            "modified": modified.map { $0 ?? NSNull() as Any },
            "folders": folders.map { ["name": $0.name, "notes": $0.noteIDs] },
        ]
        if let texts {
            object["texts"] = texts.map { $0 ?? NSNull() as Any }
        }
        return try JSONSerialization.data(withJSONObject: object)
    }

    func testParsesListingNewestFirstWithoutRecentlyDeleted() throws {
        let data = try listing(
            ids: ["id-old", "id-plan", "id-groceries", "id-deleted"],
            titles: [nil, "Plan\tQ4", "Groceries", "Old"],
            modified: [1000, 2_000_000_000, 2_000_000_060, 2_000_000_100],
            folders: [
                ("Notes", ["id-old", "id-groceries"]), ("Work", ["id-plan"]), ("Recently Deleted", ["id-deleted"]),
            ],
            texts: [nil, "Plan\tQ4\nship the notes module", "Groceries\nmilk\teggs\n", "Old"]
        )
        let notes = try NotesManager.parseListing(data, excludingFolders: ["Recently Deleted"])

        XCTAssertEqual(notes.map(\.id), ["id-groceries", "id-plan", "id-old"])
        XCTAssertEqual(notes[0].modified, Date(timeIntervalSince1970: 2_000_000_060))
        XCTAssertEqual(notes[0].folder, "Notes")
        XCTAssertEqual(notes[0].text, "Groceries\nmilk\teggs\n", "keeps the text's own newlines and tabs")
        XCTAssertEqual(notes[1].title, "Plan\tQ4")
        XCTAssertEqual(notes[1].folder, "Work")
        XCTAssertEqual(notes[2].displayTitle, "New Note", "a missing value is an empty title")
        XCTAssertEqual(notes[2].text, "")
    }

    /// The walk lists subfolders after their parents, so the deepest folder names a note.
    func testNoteGoesToTheLastFolderListingIt() throws {
        let data = try listing(
            ids: ["a", "b", "c"], titles: ["A", "B", "C"], modified: [3, 2, 1],
            folders: [("Notes", ["a", "b"]), ("Empty", []), ("Projects", ["b"])]
        )
        let notes = try NotesManager.parseListing(data, excludingFolders: [])
        XCTAssertEqual(notes.map(\.folder), ["Notes", "Projects", ""], "c was made after the folders were read")
        XCTAssertNil(notes[0].text)
    }

    /// Text that failed to read (a locked note, say) leaves the titles usable.
    func testTextOfAnotherLengthIsDropped() throws {
        let data = try listing(
            ids: ["a", "b"], titles: ["A", "B"], modified: [1, 2], folders: [("Notes", ["a", "b"])], texts: ["A"]
        )
        let notes = try NotesManager.parseListing(data, excludingFolders: [])
        XCTAssertEqual(notes.count, 2)
        XCTAssertNil(notes[0].text)
    }

    func testListsOfDifferentLengthsAreUnreadable() throws {
        let data = try listing(ids: ["a", "b"], titles: ["A"], modified: [1, 2], folders: [])
        XCTAssertThrowsError(try NotesManager.parseListing(data, excludingFolders: []))
        XCTAssertThrowsError(try NotesManager.parseListing(Data("garbage".utf8), excludingFolders: []))
    }

    func testEmptyLibrary() throws {
        let data = try listing(ids: [], titles: [], modified: [], folders: [], texts: [])
        XCTAssertEqual(try NotesManager.parseListing(data, excludingFolders: []), [])
    }

    func testBodyTextDropsTheTitleLine() {
        let note = NoteInfo(id: "a", title: "Groceries", folder: "Notes", modified: Date(), text: "Groceries\n\nmilk")
        XCTAssertEqual(note.bodyText, "milk")
        XCTAssertNil(NoteInfo(id: "a", title: "T", folder: "Notes", modified: Date(), text: "T\n").bodyText)
        XCTAssertNil(NoteInfo(id: "a", title: "T", folder: "Notes", modified: Date(), text: nil).bodyText)
    }

    func testListScriptAsksForTextOnlyWhenSearchingIt() {
        let withText = NotesManager.listScript(includeText: true)
        XCTAssertTrue(withText.contains("try { listing.texts = notes.plaintext(); } catch (error) {"))
        XCTAssertFalse(withText.contains("container"), "scripting can't use a note's container")
        XCTAssertTrue(withText.contains("notes: queue[i].notes.id()"))
        XCTAssertFalse(NotesManager.listScript(includeText: false).contains("plaintext"))
    }

    /// Every script returns its error as JSON rather than letting osascript print it.
    func testScriptsReturnErrorsAsJSON() {
        let script = NotesManager.showScript(noteID: "x")
        XCTAssertTrue(script.hasPrefix("function run() {\nconst Notes = Application(\"com.apple.Notes\");\ntry {\n"))
        XCTAssertTrue(script.hasSuffix(
            "return JSON.stringify({ error: { number: number, message: String(error.message) } });\n}\n}"
        ))
    }

    func testShowAndCreateScripts() {
        let show = NotesManager.showScript(noteID: #"x-coredata://A/ICNote/p1"#)
        XCTAssertTrue(show.contains(#"Notes.show(Notes.notes.byId("x-coredata://A/ICNote/p1"));"#))
        XCTAssertTrue(show.contains("Notes.activate();"))

        let inDefault = NotesManager.createScript(title: #"Fish & "chips" <3 \ "#, folder: nil)
        XCTAssertTrue(inDefault.contains(#"Notes.Note({ body: "<h1>Fish &amp; \"chips\" &lt;3 \\ </h1>" })"#))
        XCTAssertTrue(inDefault.contains("Notes.defaultAccount.defaultFolder.notes.push(note);"))
        XCTAssertTrue(inDefault.contains("Notes.show(note);"))

        let inFolder = NotesManager.createScript(title: "Idea", folder: #"Work "2026""#)
        XCTAssertTrue(inFolder.contains(#"Notes.folders.byName("Work \"2026\"").notes.push(note);"#))
    }

    func testScriptErrorsSayWhatToDo() throws {
        let output = #"{"error":{"number":-1743,"message":"Not authorized to send Apple events to Notes."}}"#
        let denied = try XCTUnwrap(NotesManager.scriptFailure(in: output))
        XCTAssertEqual(
            denied,
            NotesManager.ScriptFailure(number: -1743, message: "Not authorized to send Apple events to Notes.")
        )
        XCTAssertNil(NotesManager.scriptFailure(in: #"{"ids":[]}"#))
        XCTAssertEqual(NotesManager.scriptFailure(in: #"{"error":{"number":null,"message":"x"}}"#)?.number, nil)

        let notAuthorized = NotesManager.scriptError(code: -1743, message: "x", missing: nil)
        XCTAssertEqual(notAuthorized as? NotesError, .notAuthorized)
        let gone = NotesManager.scriptError(code: -1728, message: "x", missing: .noteNotFound)
        XCTAssertEqual(gone as? NotesError, .noteNotFound)
        let other = NotesManager.scriptError(code: -1728, message: "Can't get object.", missing: nil)
        XCTAssertEqual(other.localizedDescription, "AppleScript error: Can't get object. (-1728)")

        XCTAssertEqual(NotesManager.errorCode(in: "execution error: Error: Not authorized. (-1743)"), -1743)
        XCTAssertNil(NotesManager.errorCode(in: "no number"))
    }

    /// The listing script itself, run by osascript against a stand-in for Notes: one note's
    /// unreadable text (a locked note) fails the bulk read, and only that note loses it.
    func testListingReadsTextsOneByOneWhenTheBulkReadFails() async throws {
        let stub = """
        function fakeNotes() {
          const library = [
            { id: "p1", name: "Groceries", text: "Groceries\\nmilk", folder: "Notes" },
            { id: "p2", name: "Diary", text: null, folder: "Notes" },
            { id: "p3", name: "Plan", text: "Plan\\nship it", folder: "Work" },
          ];
          const text = note => { if (note.text === null) { throw new Error("locked"); } return note.text; };
          const folder = name => ({
            name: () => name,
            notes: { id: () => library.filter(note => note.folder === name).map(note => note.id) },
            folders: () => [],
          });
          return {
            notes: {
              id: () => library.map(note => note.id),
              name: () => library.map(note => note.name),
              modificationDate: () => library.map((note, index) => new Date(1000 * (index + 1))),
              plaintext: () => library.map(text),
              byId: id => ({ plaintext: () => text(library.find(note => note.id === id)) }),
            },
            folders: () => [folder("Notes"), folder("Work")],
          };
        }

        """
        let script = NotesManager.listScript(includeText: true)
            .replacingOccurrences(of: #"Application("com.apple.Notes")"#, with: "fakeNotes()")
        // Never let the test reach the real Notes (that would ask to control it).
        guard !script.contains("Application(") else {
            return XCTFail("the listing script names Notes some other way; update the stand-in")
        }
        let output = try await AppleScriptRunner.run(stub + script, language: .javaScript, timeout: 10)
        let notes = try NotesManager.parseListing(Data(output.utf8), excludingFolders: [])

        XCTAssertEqual(notes.map(\.id), ["p3", "p2", "p1"])
        XCTAssertEqual(notes.map(\.text), ["Plan\nship it", "", "Groceries\nmilk"])
        XCTAssertEqual(notes.map(\.folder), ["Work", "Notes", "Notes"])
        XCTAssertEqual(notes[0].modified, Date(timeIntervalSince1970: 3))
    }

    func testTrashFolderNameFollowsTheChosenLocalization() {
        let table: [String: Any] = [
            "en": ["Recently Deleted": "Recently Deleted"],
            "de": ["Recently Deleted": "Zuletzt gelöscht"],
            "it": ["Recently Deleted": "Eliminate"],
            "LocProvenance": ["en": "x"],
        ]
        XCTAssertEqual(NotesManager.trashFolderNames(in: table, preferences: ["de-DE"]), [
            "Recently Deleted", "Zuletzt gelöscht",
        ])
        XCTAssertEqual(NotesManager.trashFolderNames(in: table, preferences: ["en-US", "it-IT"]), ["Recently Deleted"])
        XCTAssertEqual(NotesManager.trashFolderNames(in: [:], preferences: ["de-DE"]), ["Recently Deleted"])
    }
}

final class NotesModuleTests: XCTestCase {
    private let groceries = NoteInfo(
        id: "x-coredata://A/ICNote/p1", title: "Groceries", folder: "Home",
        modified: Date(timeIntervalSinceNow: -60), text: "Groceries\nmilk\neggs"
    )
    private let plan = NoteInfo(
        id: "x-coredata://A/ICNote/p2", title: "Q4 plan", folder: "Work",
        modified: Date(timeIntervalSinceNow: -3600), text: "Q4 plan\nShip the notes module, then buy eggs for the team"
    )

    func testConfigDecodesPartialSections() throws {
        let config = try JSONDecoder().decode(NotesConfig.self, from: Data(#"{ "newNoteFolder": "Inbox" }"#.utf8))
        XCTAssertEqual(config.newNoteFolder, "Inbox")
        XCTAssertEqual(config.maxResults, 100)
        XCTAssertTrue(config.searchContent)
        XCTAssertEqual(try JSONDecoder().decode(NotesConfig.self, from: Data("{}".utf8)), NotesConfig())
    }

    func testValidation() {
        XCTAssertTrue(NotesModule.validate(NotesConfig()).isValid)
        var config = NotesConfig()
        config.maxResults = -1
        config.newNoteFolder = " "
        XCTAssertEqual(NotesModule.validate(config).errors.count, 2)
    }

    func testFixedActionsAndNoteRows() async {
        let fixed = await NotesModule().fixedActions(appIcon: nil)
        XCTAssertEqual(fixed.map(\.id.rawValue), ["notes/search", "notes/create"])
        XCTAssertTrue(fixed.allSatisfy { $0.parameters.allSatisfy(\.isRequired) }, "the picker prompts only for these")

        let rows = NotesModule.noteActions([groceries, plan], maxResults: 1, appIcon: nil)
        XCTAssertEqual(rows.map(\.id), [NotesModule.actionID(for: groceries)])
        XCTAssertEqual(rows[0].id.rawValue, "notes/note.\(StableID.hash(groceries.id))")
        XCTAssertEqual(rows[0].title, "Groceries")
        XCTAssertEqual(rows[0].subtitle, "Home")
        XCTAssertTrue(rows[0].keywords.contains("groceries"))
        XCTAssertTrue(NotesModule.noteActions([groceries], maxResults: 0, appIcon: nil).isEmpty)
    }

    func testEnabledActionsTakeNamesAndTheNoteFamily() async {
        var config = NotesConfig()
        config.enabledActions = ["search", "note"]
        let actions = await NotesModule().fixedActions(appIcon: nil)
            + NotesModule.noteActions([groceries], maxResults: 10, appIcon: nil)
        XCTAssertEqual(
            NotesModule.enabled(actions, config: config).map(\.id),
            [ActionID("notes/search"), NotesModule.actionID(for: groceries)]
        )
    }

    /// Keybindings are checked at config load: resolving IDs must not script Notes.
    func testResolvesIDsWithoutAListing() async {
        let module = NotesModule()
        let create = await module.action(id: ActionID("notes/create"))
        XCTAssertEqual(create?.title, "New Note")
        let unlisted = await module.action(id: ActionID("notes/note.abc"))
        XCTAssertEqual(unlisted?.id, ActionID("notes/note.abc"), "runs once notes are listed")
        let unknown = await module.action(id: ActionID("notes/bogus"))
        XCTAssertNil(unknown)

        var config = NotesConfig()
        config.enabledActions = ["search"]
        await module.configDidUpdate(config)
        let disabled = await module.action(id: ActionID("notes/create"))
        XCTAssertNil(disabled)
    }

    func testSearchOptionsShowWhereTheTextMatches() {
        let options = NotesModule.searchOptions([groceries, plan], query: "buy eggs", appURL: nil)
        XCTAssertEqual(options.map(\.id), [groceries.id, plan.id])
        XCTAssertTrue(options[0].subtitle?.hasPrefix("Home · ") ?? false, "no match in its text")
        XCTAssertEqual(options[1].subtitle, "…the notes module, then buy eggs for the team")

        // The picker keeps the passage's note even though its title doesn't match.
        XCTAssertEqual(options.fuzzyFiltered(by: "buy eggs").map(\.id), [plan.id])
    }

    func testTitleMatchKeepsFolderAndAge() {
        let options = NotesModule.searchOptions([groceries], query: "GROC", appURL: nil)
        XCTAssertTrue(options[0].subtitle?.hasPrefix("Home · ") ?? false)
        XCTAssertEqual(NotesModule.searchOptions([groceries], query: "", appURL: nil)[0].label, "Groceries")
    }

    func testPassageIsOneLineAroundTheMatch() {
        let text = "Intro line\n" + String(repeating: "filler ", count: 10) + "the\tKEY\nphrase "
            + String(repeating: "tail ", count: 40)
        let passage = NotesModule.passage(in: text, around: "key")
        XCTAssertEqual(passage?.hasPrefix("…"), true)
        XCTAssertEqual(passage?.hasSuffix("…"), true)
        XCTAssertEqual(passage?.contains("the KEY phrase"), true)
        XCTAssertFalse(passage?.contains("\n") ?? true)
        XCTAssertEqual(NotesModule.passage(in: "key at the start", around: "KEY"), "key at the start")
        XCTAssertNil(NotesModule.passage(in: "nothing here", around: "key"))
    }

    // MARK: - Search Notes

    func testSearchNotesListsAgainOnceStale() async {
        let library = FakeLibrary()
        library.set([groceries])
        let module = NotesModule(lister: { try library.list(includeText: $0) })
        let search = ActionID("notes/search")

        var titles = await module.provideParameterOptions(for: "note", in: search, query: "").map(\.label)
        XCTAssertEqual(titles, ["Groceries"])
        library.set([plan, groceries])
        titles = await module.provideParameterOptions(for: "note", in: search, query: "").map(\.label)
        XCTAssertEqual(titles, ["Groceries"], "a fresh listing answers without listing again")
        XCTAssertEqual(library.listings, 1)

        // Whether or not Notes is running: Search Notes may launch it.
        await module.markStale()
        titles = await module.provideParameterOptions(for: "note", in: search, query: "").map(\.label)
        XCTAssertEqual(titles, ["Q4 plan", "Groceries"])
        XCTAssertEqual(library.listings, 2)
    }

    /// The picker doesn't filter Search Notes' options (`rankedByModule`), so the row
    /// saying why there are no notes stays up whatever the user types.
    func testCouldNotReadRowSurvivesATypedQuery() async {
        let library = FakeLibrary()
        library.set([], error: NotesError.notAuthorized)
        let module = NotesModule(lister: { try library.list(includeText: $0) })
        let search = ActionID("notes/search")

        let options = await module.provideParameterOptions(for: "note", in: search, query: "groceries")
        XCTAssertEqual(options.map(\.id), [""])
        XCTAssertEqual(options.first?.subtitle, NotesError.notAuthorized.localizedDescription)
        let parameter = await module.fixedActions(appIcon: nil).first { $0.id == search }?.parameters.first
        XCTAssertEqual(parameter?.rankedByModule, true)

        // Without a listing, every query tries again: once allowed, the notes come up.
        library.set([groceries])
        let retried = await module.provideParameterOptions(for: "note", in: search, query: "groc")
        XCTAssertEqual(retried.map(\.label), ["Groceries"])
    }

    func testModuleRanksOptionsLikeThePicker() async {
        let library = FakeLibrary()
        library.set([groceries, plan])
        let module = NotesModule(lister: { try library.list(includeText: $0) })
        let search = ActionID("notes/search")

        let byText = await module.provideParameterOptions(for: "note", in: search, query: "buy eggs")
        XCTAssertEqual(byText.map(\.id), [plan.id])
        let byTitle = await module.provideParameterOptions(for: "note", in: search, query: "groc")
        XCTAssertEqual(byTitle.map(\.id), [groceries.id])
        XCTAssertNotNil(byTitle.first?.labelHighlightRanges)
        let everything = await module.provideParameterOptions(for: "note", in: search, query: "")
        XCTAssertEqual(everything.map(\.id), [groceries.id, plan.id])
    }
}

/// The notes a test's `NotesModule` lists, and how often it asked.
private final class FakeLibrary: @unchecked Sendable {
    private let lock = NSLock()
    private var notes: [NoteInfo] = []
    private var error: Error?
    private var count = 0

    var listings: Int {
        lock.withLock { count }
    }

    func set(_ notes: [NoteInfo], error: Error? = nil) {
        lock.withLock {
            self.notes = notes
            self.error = error
        }
    }

    func list(includeText _: Bool) throws -> [NoteInfo] {
        try lock.withLock {
            count += 1
            if let error {
                throw error
            }
            return notes
        }
    }
}
