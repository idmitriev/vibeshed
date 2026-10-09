@testable import Vibeshed
import XCTest

final class SpotifyCLIParserTests: XCTestCase {
    /// Shaped like `spotify_cli search <query> --format json` (Spotify 1.3.4).
    static let searchOutput = Data("""
    {
      "artists": [{"uri": "spotify:artist:a1", "name": "The Band", "image": "spotify:image:ab6761610000f178aaaa"}],
      "tracks": [
        {"uri": "spotify:track:t1", "name": "First", "artists": ["The Band", "Guest"],
         "image": "spotify:image:ab67616d00004851bbbb"},
        {"uri": "spotify:track:t2", "name": "Second", "artists": ["The Band"],
         "image": "spotify:image:ab67616d00004851cccc"},
        {"uri": "spotify:track:t3", "name": "Third", "artists": ["The Band"]}
      ],
      "albums": [{"uri": "spotify:album:b1", "name": "Record", "artists": ["The Band"],
                  "image": "spotify:image:ab67616d00004851dddd"}],
      "playlists": [
        {"uri": "spotify:playlist:p1", "name": "Mix", "author": "someone",
         "image": "https://image-cdn-fa.spotifycdn.com/image/ab67706c0000da84eeee"}
      ],
      "shows": [],
      "episodes": [{"uri": "spotify:episode:e1", "name": "Talk", "image": "spotify:image:ffff"}],
      "audiobooks": [],
      "top_recommendations": {
        "title": "",
        "playlists": [
          {"uri": "spotify:playlist:p1", "name": "Mix", "author": "someone"},
          {"uri": "spotify:playlist:p2", "name": "This Is The Band", "author": "Spotify"}
        ]
      },
      "categories_order": ["albums", "tracks", "audioepisodes", "artists"]
    }
    """.utf8)

    private let allTypes = ["track", "album", "artist", "playlist"]

    func testFollowsSpotifysRankingThenTheRestInConfigOrder() throws {
        let items = try SpotifyCLIParser.searchItems(Self.searchOutput, types: allTypes, limitPerType: 10)
        XCTAssertEqual(items.map(\.uri), [
            "spotify:album:b1",
            "spotify:track:t1", "spotify:track:t2", "spotify:track:t3",
            "spotify:artist:a1",
            // Not in categories_order: after the ranked types. Recommendations join the
            // playlists without repeating one.
            "spotify:playlist:p1", "spotify:playlist:p2",
        ])
        XCTAssertEqual(items.map(\.kind), [.album, .track, .track, .track, .artist, .playlist, .playlist])
    }

    func testCapsEachTypeAndLeavesOutUnconfiguredOnes() throws {
        let items = try SpotifyCLIParser.searchItems(Self.searchOutput, types: ["playlist", "track"], limitPerType: 1)
        XCTAssertEqual(items.map(\.uri), ["spotify:track:t1", "spotify:playlist:p1"])
    }

    func testDescribesEachResult() throws {
        let items = try SpotifyCLIParser.searchItems(Self.searchOutput, types: allTypes, limitPerType: 10)
        let byURI = Dictionary(uniqueKeysWithValues: items.map { ($0.uri, $0) })
        XCTAssertEqual(byURI["spotify:track:t1"]?.subtitle, "Song · The Band, Guest")
        XCTAssertEqual(byURI["spotify:album:b1"]?.subtitle, "Album · The Band")
        XCTAssertEqual(byURI["spotify:artist:a1"]?.subtitle, "Artist")
        XCTAssertEqual(byURI["spotify:playlist:p2"]?.subtitle, "Playlist · Spotify")

        let track = try XCTUnwrap(byURI["spotify:track:t1"])
        XCTAssertEqual(track.artworkURL?.absoluteString, "https://i.scdn.co/image/ab67616d00004851bbbb")
        XCTAssertEqual(track.previewArtworkURL?.absoluteString, "https://i.scdn.co/image/ab67616d00001e02bbbb")
        XCTAssertNil(byURI["spotify:track:t3"]?.artworkURL)
    }

    func testSkipsEntriesWithoutAURIOrName() throws {
        let output = Data(#"{"tracks": [{"name": "No URI"}, {"uri": "spotify:track:x", "name": ""}]}"#.utf8)
        XCTAssertEqual(try SpotifyCLIParser.searchItems(output, types: allTypes, limitPerType: 10), [])
    }

    func testArtworkURLs() {
        XCTAssertEqual(SpotifyArtwork.url("spotify:image:abc")?.absoluteString, "https://i.scdn.co/image/abc")
        let mosaic = "https://mosaic.scdn.co/640/x"
        XCTAssertEqual(SpotifyArtwork.url(mosaic)?.absoluteString, mosaic)
        XCTAssertNil(SpotifyArtwork.url("http://insecure.example/x"))
        XCTAssertNil(SpotifyArtwork.url(""))

        let artist = SpotifyArtwork.url("spotify:image:ab6761610000f178959527d2")
        XCTAssertEqual(
            SpotifyArtwork.larger(artist)?.absoluteString, "https://i.scdn.co/image/ab67616100005174959527d2"
        )
        let other = URL(string: "https://image-cdn-fa.spotifycdn.com/image/ab67706c0000da84eeee")
        XCTAssertEqual(SpotifyArtwork.larger(other), other)
    }

    func testLibraryAndStatusOutput() throws {
        let contains = Data(#"{"contains":{"spotify:track:a":true,"spotify:album:b":false}}"#.utf8)
        XCTAssertTrue(try SpotifyCLIParser.contains(contains, uri: "spotify:track:a"))
        XCTAssertFalse(try SpotifyCLIParser.contains(contains, uri: "spotify:album:b"))
        XCTAssertThrowsError(try SpotifyCLIParser.contains(Data("[]".utf8), uri: "spotify:track:a"))

        XCTAssertTrue(SpotifyCLIParser.isReady(Data(#"{"running":true,"logged_in":true}"#.utf8)))
        XCTAssertFalse(SpotifyCLIParser.isReady(Data(#"{"running":true,"logged_in":false}"#.utf8)))
        XCTAssertFalse(SpotifyCLIParser.isReady(Data(#"{"running":false}"#.utf8)))
        XCTAssertFalse(SpotifyCLIParser.isReady(Data("not json".utf8)))
    }

    func testRecognizesTheNotRunningError() {
        XCTAssertEqual(SpotifyCLIError(message: "Spotify desktop client is not running"), .notRunning)
        XCTAssertEqual(
            SpotifyCLIError(message: "library contains failed: client connection failed"),
            .failed("library contains failed: client connection failed")
        )
    }

    func testSearchPrompt() {
        XCTAssertEqual(SpotifyItemType.searchPrompt(for: allTypes), "Song, album, artist or playlist")
        XCTAssertEqual(SpotifyItemType.searchPrompt(for: ["track", "artist"]), "Song or artist")
        XCTAssertEqual(SpotifyItemType.searchPrompt(for: ["album"]), "Album")
    }
}

final class SpotifyResponseParserTests: XCTestCase {
    func testParsesWebAPISearchIntoItems() throws {
        let response = Data("""
        {
          "tracks": {"items": [{
            "uri": "spotify:track:t1", "name": "First",
            "artists": [{"name": "The Band"}],
            "album": {"images": [{"url": "https://i.scdn.co/image/large"}, {"url": "https://i.scdn.co/image/small"}]}
          }]},
          "playlists": {"items": [null, {
            "uri": "spotify:playlist:p1", "name": "Mix", "owner": {"display_name": "someone"},
            "images": [{"url": "https://i.scdn.co/image/cover"}], "items": {"total": 12}
          }]}
        }
        """.utf8)
        let items = try SpotifyResponseParser.parseSearchResults(response, types: ["track", "album", "playlist"])
        XCTAssertEqual(items.map(\.uri), ["spotify:track:t1", "spotify:playlist:p1"])
        XCTAssertEqual(items[0].subtitle, "Song · The Band")
        XCTAssertEqual(items[0].artworkURL?.absoluteString, "https://i.scdn.co/image/small")
        XCTAssertEqual(items[0].previewArtworkURL?.absoluteString, "https://i.scdn.co/image/large")
        XCTAssertEqual(items[1].subtitle, "Playlist · someone")
    }

    func testLibraryURLEncodesTheURI() throws {
        let url = try SpotifySearchClient.libraryURL("me/library/contains", uri: "spotify:track:abc")
        XCTAssertEqual(url.absoluteString, "https://api.spotify.com/v1/me/library/contains?uris=spotify%3Atrack%3Aabc")
    }
}

final class SpotifyModuleSearchTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A stand-in `spotify_cli` that records its arguments, one per line, and answers
    /// `search` with `searchOutput` — or fails with `error`.
    private func fakeCLI(error: String? = nil) throws -> SpotifyCLI {
        let output = directory.appendingPathComponent("search.json")
        try SpotifyCLIParserTests.searchOutput.write(to: output)
        let script = directory.appendingPathComponent("spotify_cli")
        let answer = error.map { "echo '\($0)' >&2; exit 1" } ?? "cat '\(output.path)'"
        try """
        #!/bin/sh
        printf '%s\\n' "$@" > '\(directory.appendingPathComponent("arguments").path)'
        \(answer)
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return SpotifyCLI(executableURL: script)
    }

    private func recordedArguments() throws -> [String] {
        try String(contentsOf: directory.appendingPathComponent("arguments"), encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init)
    }

    func testListsResultsAsOptionsThatPlayByURI() async throws {
        let cli = try fakeCLI()
        let module = SpotifyModule(locateCLI: { cli })

        let options = await module.searchOptions("  the band ")
        XCTAssertEqual(options.first?.id, "spotify:album:b1")
        XCTAssertEqual(options.first?.label, "Record")
        XCTAssertEqual(options.first?.subtitle, "Album · The Band")
        XCTAssertEqual(options.count, 7)
        // Ten of each of the four default types, in one search.
        XCTAssertEqual(try recordedArguments(), ["search", "the band", "--limit", "40", "--format", "json"])
    }

    func testOneTypeSearchesOnlyThatTypeAndDashedQueriesStayQueries() async throws {
        let cli = try fakeCLI()
        let module = SpotifyModule(locateCLI: { cli })
        var config = SpotifyConfig()
        config.searchTypes = ["track"]
        config.maxSearchResults = 2
        await module.configDidUpdate(config)

        let options = await module.searchOptions("-ish")
        XCTAssertEqual(options.map(\.id), ["spotify:track:t1", "spotify:track:t2"])
        XCTAssertEqual(
            try recordedArguments(), ["search", " -ish", "--limit", "2", "--type", "track", "--format", "json"]
        )
    }

    func testShortQueriesDontSearch() async throws {
        let cli = try fakeCLI()
        let module = SpotifyModule(locateCLI: { cli })
        let options = await module.searchOptions(" a ")
        XCTAssertEqual(options.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("arguments").path))
    }

    func testAFailedSearchShowsWhy() async throws {
        let cli = try fakeCLI(error: "search failed: HTTP request failed")
        let module = SpotifyModule(locateCLI: { cli })

        let options = await module.searchOptions("the band")
        XCTAssertEqual(options.map(\.label), ["search failed: HTTP request failed"])
        let result = try await module.playResult(XCTUnwrap(options.first?.id))
        guard case let .showResult(_, body) = result else { return XCTFail("expected the error, got \(result)") }
        XCTAssertEqual(body, "search failed: HTTP request failed")
    }

    func testSearchActionAsksForAResultTheModuleRanks() async throws {
        let cli = try fakeCLI()
        let module = SpotifyModule(locateCLI: { cli })
        var config = SpotifyConfig()
        // Building it would ask the real Spotify what's playing.
        config.showNowPlaying = false
        await module.configDidUpdate(config)

        let actions = await module.provideActions(query: "", scoring: ScoringContext(
            usageCounts: [:], lastUsedDates: [:], query: "", systemContext: nil
        ))
        let search = try XCTUnwrap(actions.first { $0.id.actionName == "search" })
        let parameter = try XCTUnwrap(search.parameters.first)
        XCTAssertEqual(parameter.id, SpotifyModule.itemParameterID)
        XCTAssertEqual(parameter.label, "Song, album, artist or playlist")
        XCTAssertTrue(parameter.rankedByModule)
        guard case .dynamicSelection = parameter.type else { return XCTFail("expected a dynamic selection") }
    }

    func testNoSearchWithoutTheCLIOrAClientID() async {
        let module = SpotifyModule(locateCLI: { nil })
        var config = SpotifyConfig()
        config.showNowPlaying = false
        await module.configDidUpdate(config)

        let actions = await module.provideActions(query: "", scoring: ScoringContext(
            usageCounts: [:], lastUsedDates: [:], query: "", systemContext: nil
        ))
        XCTAssertFalse(actions.contains { $0.id.actionName == "search" })
        XCTAssertTrue(actions.contains { $0.id.actionName == "quickSearch" })
        let options = await module.searchOptions("the band")
        XCTAssertEqual(options.count, 0)
    }
}
