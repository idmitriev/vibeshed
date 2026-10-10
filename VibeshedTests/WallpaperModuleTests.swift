import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Vibeshed
import XCTest

final class WallpaperModuleTests: XCTestCase {
    private let scoring = ScoringContext(usageCounts: [:], lastUsedDates: [:], query: "", systemContext: nil)

    func testDefaultsAreValidAndSkipUnsplashWithoutKey() {
        let config = WallpaperConfig()
        XCTAssertEqual(config.validationErrors(), [])
        XCTAssertEqual(config.activeSources, [.wallhaven, .artic, .rijksmuseum, .met])

        var withKey = config
        withKey.unsplashAccessKey = "key"
        XCTAssertEqual(withKey.activeSources, WallpaperSourceID.allCases)
    }

    func testValidation() {
        var config = WallpaperConfig()
        config.sources = ["met", "flickr", "met"]
        config.maxResultsPerSource = 0
        config.orientation = "sideways"
        config.unsplashAccessKey = " "
        XCTAssertEqual(config.validationErrors().count, 5)
    }

    func testActions() async throws {
        let module = WallpaperModule()
        await module.configDidUpdate(WallpaperConfig(sources: ["met", "wallhaven"]))
        let actions = await module.buildActions()
        XCTAssertEqual(actions.map(\.id.actionName), ["search", "random", "openSourcePage"])
        XCTAssertEqual(actions[0].parameters.map(\.id), ["source", "wallpaper"])
        XCTAssertEqual(actions[1].parameters.map(\.id), ["source", "query"])
        XCTAssertTrue(try XCTUnwrap(actions[0].parameters.last).rankedByModule)
        guard case let .selection(sources) = actions[0].parameters[0].type else {
            return XCTFail("expected a selection")
        }
        XCTAssertEqual(sources.map(\.id), ["all", "met", "wallhaven"])

        // One source: nothing to choose.
        await module.configDidUpdate(WallpaperConfig(sources: ["met"], enabledActions: ["random"]))
        let single = await module.provideActions(query: "", scoring: scoring)
        XCTAssertEqual(single.map(\.id.actionName), ["random"])
        XCTAssertEqual(single.first?.parameters.map(\.id), ["query"])
    }

    func testSourceValues() {
        let config = WallpaperConfig(sources: ["met", "wallhaven"])
        XCTAssertEqual(WallpaperModule.sources(for: "all", config: config), [.met, .wallhaven])
        XCTAssertEqual(WallpaperModule.sources(for: nil, config: config), [.met, .wallhaven])
        XCTAssertEqual(WallpaperModule.sources(for: "wallhaven", config: config), [.wallhaven])
    }

    func testSubjectStep() {
        let anything = WallpaperModule.subjectOptions("  ", sources: [.met])
        XCTAssertEqual(anything.map(\.id), ["*"])
        XCTAssertEqual(anything.first?.subtitle, "A random pick from The Met’s featured images")
        let storm = WallpaperModule.subjectOptions("storm ", sources: [.met, .wallhaven])
        XCTAssertEqual(storm.map(\.id), ["storm"])
        XCTAssertEqual(storm.first?.label, "“storm”")
        XCTAssertEqual(WallpaperModule.subject("*"), "")
        XCTAssertEqual(WallpaperModule.subject(nil), "")
    }

    /// With a subject, a random pick searches; when nothing matches it says so instead
    /// of setting anything.
    func testRandomWithASubjectSearches() async throws {
        let (module, calls) = await makeModule(sources: ["wallhaven", "met"], stubs: [:])
        let result = try await module.setRandomWallpaper(source: "all", query: "storm")
        guard case let .showResult(_, body) = result else { return XCTFail("expected a message") }
        XCTAssertEqual(body, "Nothing found for “storm”")
        let wallhaven = await calls.queries[.wallhaven]
        let met = await calls.queries[.met]
        XCTAssertEqual(wallhaven, ["storm"])
        XCTAssertEqual(met, ["storm"])
    }

    func testSearchMixesSourcesAndReportsFailures() async throws {
        let (module, calls) = await makeModule(sources: ["wallhaven", "rijksmuseum", "met", "artic"], stubs: [
            .wallhaven: .results([sample(.wallhaven, "w1"), sample(.wallhaven, "w2")]),
            .rijksmuseum: .results([sample(.rijksmuseum, "r1")]),
            .met: .failure(.rateLimited(.met)),
            .artic: .failure(.blocked(.artic)),
        ])

        let options = await search(module, "storm", source: "all")
        // A source that blocks apps isn't reported in every mixed search.
        XCTAssertEqual(options.map(\.id), ["wallhaven:w1", "rijksmuseum:r1", "wallhaven:w2", "message:met"])
        XCTAssertEqual(options[0].iconURL?.absoluteString, "https://example.com/wallhaven/w1/thumb.jpg")

        // Its own search does.
        let artic = await search(module, "storm", source: "artic")
        XCTAssertEqual(artic.map(\.id), ["message:artic"])
        XCTAssertTrue(artic[0].label.contains("browser check"))

        // Mixed searches leave the blocked source alone for a while.
        _ = await search(module, "wave", source: "all")
        let articQueries = await calls.queries[.artic]
        XCTAssertEqual(articQueries, ["storm", "storm"])

        guard case let .showResult(title, body) = try await module.setWallpaper(optionID: "message:met") else {
            return XCTFail("expected the error message")
        }
        XCTAssertEqual(title, "The Met")
        XCTAssertTrue(body.contains("rate limit"))
        let queries = await calls.queries[.wallhaven]
        XCTAssertEqual(queries, ["storm", "wave"])
    }

    /// Results stay with the source that sent them. Release builds of 0.8.0 filed every
    /// source's under Wallhaven (the first case), so searching The Met alone listed nothing.
    /// Only optimized builds went wrong; run with `swift test -c release -Xswiftc -enable-testing`.
    func testASourcesResultsStayWithIt() async {
        let (module, _) = await makeModule(sources: ["wallhaven", "rijksmuseum", "met"], stubs: [
            .wallhaven: .results([sample(.wallhaven, "w1")]),
            .rijksmuseum: .results([sample(.rijksmuseum, "r1")]),
            .met: .results([sample(.met, "1"), sample(.met, "2")]),
        ])
        let met = await search(module, "storm", source: "met")
        XCTAssertEqual(met.map(\.id), ["met:1", "met:2"])
        let rijksmuseum = await search(module, "", source: "rijksmuseum")
        XCTAssertEqual(rijksmuseum.map(\.id), ["rijksmuseum:r1"])
    }

    /// Lookups come back in the identifiers' order (the API's ranking), however they finish.
    func testLookupsKeepTheIdentifiersOrder() async throws {
        let found = try await WallpaperLookup.all(["1", "2", "3", "4"]) { itemID in
            // The first answers last.
            try await Task.sleep(for: .milliseconds(10 * (5 - (Int(itemID) ?? 0))))
            return itemID == "3" ? nil : sample(.met, itemID)
        }
        XCTAssertEqual(found.map(\.id), ["met:1", "met:2", "met:4"])
    }

    func testRepeatedSearchesUseTheCacheAndShortQueriesShowFeatured() async {
        let (module, calls) = await makeModule(sources: ["wallhaven"], stubs: [
            .wallhaven: .results([sample(.wallhaven, "w1")]),
        ])
        _ = await search(module, "Storm ")
        _ = await search(module, "storm")
        _ = await search(module, "s")
        _ = await search(module, "")

        let queries = await calls.queries[.wallhaven]
        XCTAssertEqual(queries, ["Storm", ""])
    }

    func testListedWallpapersResolveWithoutTheSource() async throws {
        let (module, calls) = await makeModule(sources: ["met"], stubs: [.met: .results([sample(.met, "1")])])
        _ = await search(module, "")
        let listed = try await module.wallpaper(optionID: "met:1")
        XCTAssertEqual(listed?.id, "met:1")

        // Not listed (an alias or URI): asked of the source.
        let looked = try await module.wallpaper(optionID: "met:2")
        XCTAssertNil(looked)
        let lookups = await calls.lookups
        XCTAssertEqual(lookups, ["met:2"])
    }

    func testInterleaving() {
        let lists = [[sample(.met, "1"), sample(.met, "2"), sample(.met, "3")], [sample(.wallhaven, "a")], []]
        XCTAssertEqual(
            WallpaperModule.interleaved(lists).map(\.id), ["met:1", "wallhaven:a", "met:2", "met:3"]
        )
    }

    func testSubtitleAndCredit() {
        let painting = sample(.met, "1", credit: "Vincent van Gogh", date: "1887")
        XCTAssertEqual(WallpaperModule.subtitle(for: painting), "The Met · Vincent van Gogh · 1887")
        XCTAssertEqual(WallpaperModule.creditLine(painting), "Painting 1 — Vincent van Gogh, 1887 · The Met")
        let upload = sample(.wallhaven, "a", detail: "General · 3 favorites")
        XCTAssertEqual(WallpaperModule.subtitle(for: upload), "Wallhaven · General · 3 favorites")
    }

    // MARK: - Helpers

    /// The search step's options, after `source` was picked (none: as from a URI without it).
    private func search(_ module: WallpaperModule, _ query: String, source: String? = nil) async -> [ParameterOption] {
        await module.provideParameterOptions(
            for: "wallpaper", in: ActionID("wallpaper/search"), query: query,
            collected: ParameterValues(source.map { ["source": $0] } ?? [:])
        )
    }

    private func makeModule(
        sources: [String],
        stubs: [WallpaperSourceID: StubSource.Answer]
    ) async -> (WallpaperModule, StubCalls) {
        let calls = StubCalls()
        let module = WallpaperModule { sourceID, _ in
            StubSource(id: sourceID, answer: stubs[sourceID] ?? .results([]), calls: calls)
        }
        await module.configDidUpdate(WallpaperConfig(sources: sources))
        return (module, calls)
    }
}

final class WallpaperPlacementTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testArtworkOfAnotherShapeIsFittedOnItsEdgeColor() throws {
        // 2:1, red border around a blue middle.
        let file = try writeImage(width: 200, height: 100, border: 20)
        XCTAssertEqual(try XCTUnwrap(WallpaperPlacement.aspectRatio(of: file)), 2, accuracy: 0.001)

        func placement(_ source: WallpaperSourceID, _ scaling: WallpaperScaling, screen: Double) -> WallpaperPlacement {
            let image = WallpaperPlacement.Image(file, source: source, scaling: scaling)
            return WallpaperPlacement.choose(for: image, source: source, scaling: scaling, screenAspectRatio: screen)
        }
        guard case let .fit(matte) = placement(.met, .auto, screen: 16 / 10) else { return XCTFail("expected fit") }
        XCTAssertGreaterThan(matte.red, 0.9)
        XCTAssertLessThan(matte.blue, 0.1)
        // On a portrait screen too.
        XCTAssertEqual(placement(.met, .auto, screen: 2 / 3.0), .fit(matte: matte))

        // Close enough to the screen's shape, or a photo: fills.
        XCTAssertEqual(placement(.met, .auto, screen: 1.9), .fill)
        XCTAssertEqual(placement(.wallhaven, .auto, screen: 1.6), .fill)
        XCTAssertEqual(placement(.met, .fill, screen: 1.6), .fill)
    }

    func testWhereFroms() throws {
        let file = try writeImage(width: 10, height: 10, border: 2)
        let image = try XCTUnwrap(URL(string: "https://images.metmuseum.org/a.jpg"))
        let page = try XCTUnwrap(URL(string: "https://www.metmuseum.org/art/collection/search/436524"))
        XCTAssertNil(WallpaperDownloads.sourcePage(of: file))

        WallpaperDownloads.setWhereFroms([image, page], of: file)
        XCTAssertEqual(WallpaperDownloads.whereFroms(of: file), [image, page])
        XCTAssertEqual(WallpaperDownloads.sourcePage(of: file), page)

        WallpaperDownloads.setWhereFroms([image], of: file)
        XCTAssertEqual(WallpaperDownloads.sourcePage(of: file), image)
    }

    func testFileNamesAndDirectory() {
        XCTAssertEqual(WallpaperDownloads.fileStem(for: sample(.unsplash, "a/b:c")), "unsplash-a_b_c")
        XCTAssertEqual(WallpaperDownloads.directory(for: WallpaperConfig()), WallpaperDownloads.defaultDirectory)
        let custom = WallpaperDownloads.directory(for: WallpaperConfig(downloadDirectory: "~/Pictures/Walls"))
        XCTAssertEqual(custom.path, NSHomeDirectory() + "/Pictures/Walls")
    }

    private func writeImage(width: Int, height: Int, border: Int) throws -> URL {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: border, y: border, width: width - 2 * border, height: height - 2 * border))
        let image = try XCTUnwrap(context.makeImage())
        let url = directory.appendingPathComponent("\(UUID().uuidString).png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
}

// MARK: - Stubs

private func sample(
    _ source: WallpaperSourceID,
    _ itemID: String,
    credit: String? = nil,
    date: String? = nil,
    detail: String? = nil
) -> OnlineWallpaper {
    let base = "https://example.com/\(source.rawValue)/\(itemID)"
    return OnlineWallpaper(
        source: source, sourceItemID: itemID, title: "Painting \(itemID)", credit: credit, creditURL: nil, date: date,
        detail: detail, pageURL: URL(string: base), thumbnailURL: URL(string: base + "/thumb.jpg")!,
        previewURL: URL(string: base + "/preview.jpg")!, image: .fixed(URL(string: base + "/full.jpg")!),
        pixelWidth: nil, pixelHeight: nil, aspectRatio: nil, colors: [], license: nil, downloadTrackingURL: nil
    )
}

private actor StubCalls {
    var queries: [WallpaperSourceID: [String]] = [:]
    var lookups: [String] = []

    func searched(_ source: WallpaperSourceID, _ query: String) {
        queries[source, default: []].append(query)
    }

    func lookedUp(_ optionID: String) {
        lookups.append(optionID)
    }
}

private struct StubSource: WallpaperSource {
    enum Answer: Sendable {
        case results([OnlineWallpaper])
        case failure(WallpaperSourceError)
    }

    let id: WallpaperSourceID
    let answer: Answer
    let calls: StubCalls

    func search(_ query: String, options _: WallpaperSearchOptions) async throws -> [OnlineWallpaper] {
        await calls.searched(id, query)
        switch answer {
        case let .results(results): return results
        case let .failure(error): throw error
        }
    }

    func wallpaper(itemID: String) async throws -> OnlineWallpaper? {
        await calls.lookedUp(OnlineWallpaper.optionID(source: id, itemID: itemID))
        return nil
    }

    func random(options _: WallpaperSearchOptions) async throws -> OnlineWallpaper? {
        nil
    }
}
