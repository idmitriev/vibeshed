import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Vibeshed
import XCTest

/// Parsers run on API responses captured on 2026-10-07, trimmed to the fields they read.
final class WallpaperSourceParsingTests: XCTestCase {
    func testWallhaven() throws {
        let json = try object(#"""
        {"data": {"id": "yjzykg", "url": "https://wallhaven.cc/w/yjzykg", "favorites": 26, "category": "general",
         "dimension_x": 3888, "dimension_y": 2592, "path": "https://w.wallhaven.cc/full/yj/wallhaven-yjzykg.jpg",
         "thumbs": {"large": "https://th.wallhaven.cc/lg/yj/yjzykg.jpg",
                    "small": "https://th.wallhaven.cc/small/yj/yjzykg.jpg"},
         "colors": ["#999999", "#424153", "#cccccc"], "tags": [{"name": "mountains"}, {"name": "clouds"}],
         "uploader": {"username": "insan1e"}}}
        """#)
        let wallpaper = try XCTUnwrap(WallhavenSource.wallpaper(XCTUnwrap(json["data"] as? [String: Any])))

        XCTAssertEqual(wallpaper.id, "wallhaven:yjzykg")
        XCTAssertEqual(wallpaper.title, "mountains, clouds")
        XCTAssertEqual(wallpaper.credit, "insan1e")
        XCTAssertEqual(wallpaper.detail, "General · 26 favorites")
        XCTAssertEqual(wallpaper.resolution, "3888 × 2592")
        XCTAssertEqual(wallpaper.aspectRatio ?? 0, 1.5, accuracy: 0.001)
        XCTAssertEqual(wallpaper.colors.count, 3)
        XCTAssertEqual(
            wallpaper.downloadURL(longestSide: 3456).absoluteString,
            "https://w.wallhaven.cc/full/yj/wallhaven-yjzykg.jpg"
        )
        XCTAssertEqual(wallpaper.thumbnailURL.absoluteString, "https://th.wallhaven.cc/small/yj/yjzykg.jpg")
    }

    /// Search results carry no tags, so the size names them.
    func testWallhavenSearchResultWithoutTags() throws {
        let json = try object(#"""
        {"data": [{"id": "abc123", "dimension_x": 1920, "dimension_y": 1080,
          "path": "https://w.wallhaven.cc/full/ab/wallhaven-abc123.png",
          "thumbs": {"small": "https://th.wallhaven.cc/small/ab/abc123.jpg"}}]}
        """#)
        let wallpaper = try XCTUnwrap(WallhavenSource.parseSearch(json).first)
        XCTAssertEqual(wallpaper.title, "1920 × 1080")
        XCTAssertNil(wallpaper.credit)
    }

    func testWallhavenCategories() {
        XCTAssertEqual(WallhavenSource.categoryBits(["general", "anime"]), "110")
        XCTAssertEqual(WallhavenSource.categoryBits(["People"]), "001")
        XCTAssertEqual(WallhavenSource.categoryBits([]), "111")
    }

    /// The shape Unsplash documents for a photo.
    func testUnsplash() throws {
        let json = try object(#"""
        {"id": "Dwu85P9SOIk", "width": 4000, "height": 2667, "color": "#6E633A", "description": null,
         "alt_description": "a mountain range at dusk",
         "urls": {"raw": "https://images.unsplash.com/photo-1417325384643?ixid=abc&ixlib=rb-4.0.3",
                  "regular": "https://images.unsplash.com/photo-1417325384643?w=1080",
                  "thumb": "https://images.unsplash.com/photo-1417325384643?w=200"},
         "links": {"html": "https://unsplash.com/photos/Dwu85P9SOIk",
                   "download_location": "https://api.unsplash.com/photos/Dwu85P9SOIk/download?ixid=abc"},
         "user": {"name": "Jane Doe", "username": "janedoe", "links": {"html": "https://unsplash.com/@janedoe"}}}
        """#)
        let wallpaper = try XCTUnwrap(UnsplashSource.wallpaper(json))

        XCTAssertEqual(wallpaper.title, "A mountain range at dusk")
        XCTAssertEqual(wallpaper.credit, "Jane Doe")
        XCTAssertEqual(wallpaper.license, "Unsplash License")
        XCTAssertEqual(
            wallpaper.pageURL?.absoluteString,
            "https://unsplash.com/photos/Dwu85P9SOIk?utm_source=vibeshed&utm_medium=referral"
        )
        XCTAssertEqual(
            wallpaper.creditURL?.absoluteString,
            "https://unsplash.com/@janedoe?utm_source=vibeshed&utm_medium=referral"
        )
        XCTAssertEqual(
            wallpaper.downloadTrackingURL?.absoluteString,
            "https://api.unsplash.com/photos/Dwu85P9SOIk/download?ixid=abc"
        )
        XCTAssertEqual(
            wallpaper.downloadURL(longestSide: 3456).absoluteString,
            "https://images.unsplash.com/photo-1417325384643?ixid=abc&ixlib=rb-4.0.3&w=3456&fit=max&fm=jpg&q=90"
        )
    }

    func testArtInstituteOfChicago() throws {
        let json = try object(#"""
        {"data": [{"id": 27992, "title": "A Sunday on La Grande Jatte — 1884",
          "thumbnail": {"width": 9310, "height": 6237}, "date_display": "1884–86, border added 1888–89",
          "artist_display": "Georges Seurat (French, 1859–1891)", "medium_display": "Oil on canvas",
          "is_public_domain": true, "artist_title": "Georges Seurat",
          "image_id": "2d484387-2509-5e8e-2c43-22f9981972eb"}]}
        """#)
        let wallpaper = try XCTUnwrap(ArticSource.parseSearch(json).first)
        let iiif = "https://www.artic.edu/iiif/2/2d484387-2509-5e8e-2c43-22f9981972eb"

        XCTAssertEqual(wallpaper.id, "artic:27992")
        XCTAssertEqual(wallpaper.credit, "Georges Seurat")
        XCTAssertEqual(wallpaper.detail, "Oil on canvas")
        XCTAssertEqual(wallpaper.pageURL?.absoluteString, "https://www.artic.edu/artworks/27992")
        XCTAssertEqual(wallpaper.thumbnailURL.absoluteString, iiif + "/full/200,/0/default.jpg")
        // The largest size the Art Institute documents.
        XCTAssertEqual(wallpaper.downloadURL(longestSide: 6000).absoluteString, iiif + "/full/1686,/0/default.jpg")
        XCTAssertEqual(wallpaper.aspectRatio ?? 0, 9310.0 / 6237, accuracy: 0.001)
    }

    func testRijksmuseum() throws {
        let wallpaper = try XCTUnwrap(RijksmuseumSource.wallpaper(rijksRecord()))

        XCTAssertEqual(wallpaper.id, "rijksmuseum:200108359")
        XCTAssertEqual(wallpaper.title, "A Ship on the High Seas Caught by a Squall, Known as ‘The Gust’")
        XCTAssertEqual(wallpaper.credit, "Willem van de Velde (II)")
        XCTAssertEqual(wallpaper.date, "c. 1680")
        XCTAssertEqual(wallpaper.detail, "Painting")
        XCTAssertEqual(wallpaper.license, "Public domain")
        XCTAssertEqual(wallpaper.aspectRatio ?? 0, 63.5 / 77, accuracy: 0.001)
        XCTAssertEqual(
            wallpaper.downloadURL(longestSide: 3456).absoluteString,
            "https://iiif.micr.io/eBrWZ/full/!3456,3456/0/default.jpg"
        )
        XCTAssertEqual(wallpaper.thumbnailURL.absoluteString, "https://iiif.micr.io/eBrWZ/full/200,/0/default.jpg")
    }

    func testRijksmuseumSkipsInCopyrightAndThreeDimensionalWorks() throws {
        let inCopyright = try rijksRecord(replacing: "http://creativecommons.org/publicdomain/mark/1.0/",
                                          with: "http://rightsstatements.org/vocab/InC/1.0/")
        XCTAssertNil(RijksmuseumSource.wallpaper(inCopyright))

        let box = try rijksRecord(replacing: #""@value": "painting""#, with: #""@value": "box""#)
        XCTAssertNil(RijksmuseumSource.wallpaper(box))
    }

    func testRijksmuseumSearchAndMerge() throws {
        let json = try object(#"""
        {"orderedItems": [{"id": "https://id.rijksmuseum.nl/200108359", "type": "HumanMadeObject"},
                          {"id": "https://id.rijksmuseum.nl/20026169", "type": "HumanMadeObject"}]}
        """#)
        let titles = RijksmuseumSource.parseSearch(json)
        XCTAssertEqual(titles, ["200108359", "20026169"])
        XCTAssertEqual(RijksmuseumSource.merged(titles, ["20026169", "1"]), ["200108359", "20026169", "1"])
    }

    func testRijksmuseumExtent() throws {
        XCTAssertEqual(
            try XCTUnwrap(RijksmuseumSource.aspectRatio(fromExtent: "height 101.5 cm x width 143 cm")),
            143 / 101.5, accuracy: 0.001
        )
        XCTAssertNil(RijksmuseumSource.aspectRatio(fromExtent: "depth 7.5 cm"))
    }

    func testMet() throws {
        let json = try object(#"""
        {"objectID": 436524, "isPublicDomain": true,
         "primaryImage": "https://images.metmuseum.org/CRDImages/ep/original/DP-41223-001.jpg",
         "primaryImageSmall": "https://images.metmuseum.org/CRDImages/ep/web-large/DP-41223-001.jpg",
         "title": "Sunflowers", "artistDisplayName": "Vincent van Gogh", "culture": "", "objectDate": "1887",
         "medium": "Oil on canvas", "objectURL": "https://www.metmuseum.org/art/collection/search/436524",
         "measurements": [
           {"elementName": "Framed", "elementMeasurements": {"Depth": 6.35, "Height": 66.6751, "Width": 85.0902}},
           {"elementName": "Overall", "elementMeasurements": {"Height": 43.2, "Width": 61}}]}
        """#)
        let wallpaper = try XCTUnwrap(MetSource.wallpaper(json))

        XCTAssertEqual(wallpaper.id, "met:436524")
        XCTAssertEqual(wallpaper.credit, "Vincent van Gogh")
        XCTAssertEqual(wallpaper.date, "1887")
        XCTAssertEqual(wallpaper.aspectRatio ?? 0, 61 / 43.2, accuracy: 0.001)
        XCTAssertEqual(wallpaper.license, "Public domain (CC0)")

        var inCopyright = json
        inCopyright["isPublicDomain"] = false
        inCopyright["primaryImage"] = ""
        XCTAssertNil(MetSource.wallpaper(inCopyright))
        let search = try object(#"{"total": 2, "objectIDs": [11766, 436524]}"#)
        XCTAssertEqual(MetSource.parseSearch(search), ["11766", "436524"])
        XCTAssertEqual(MetSource.parseSearch(try object(#"{"total": 0, "objectIDs": null}"#)), [])
    }

    func testLinkedDataText() {
        XCTAssertEqual(LinkedData.text("plain"), "plain")
        XCTAssertEqual(LinkedData.text(["nl": "Landschap", "en": ["Landscape"]]), "Landscape")
        XCTAssertEqual(LinkedData.text([["@language": "nl", "@value": "ca. 1680"]]), "ca. 1680")
        XCTAssertNil(LinkedData.text(nil))
    }

    func testOptionIDs() throws {
        let parsed = try XCTUnwrap(OnlineWallpaper.parseOptionID("met:436524"))
        XCTAssertEqual(parsed.source, .met)
        XCTAssertEqual(parsed.itemID, "436524")
        XCTAssertNil(OnlineWallpaper.parseOptionID("flickr:1"))
        XCTAssertNil(OnlineWallpaper.parseOptionID("met:"))
    }

    // MARK: - Helpers

    private func object(_ json: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    private func rijksRecord(replacing target: String = "", with replacement: String = "") throws -> [String: Any] {
        let json = #"""
        {"aggregatedCHO": {"id": "https://id.rijksmuseum.nl/200108359",
          "title": {"nl": ["A Ship on the High Seas Caught by a Squall, Known as ‘The Gust’",
                           "Een schip in volle zee bij vliegende storm, bekend als ‘De windstoot’"],
                    "en": ["A Ship on the High Seas Caught by a Squall, Known as ‘The Gust’",
                           "Een schip in volle zee bij vliegende storm, bekend als ‘De windstoot’"]},
          "created": [{"@language": "en", "@value": "c. 1680"}, {"@language": "nl", "@value": "ca. 1680"}],
          "extent": [{"@language": "en", "@value": "height 77 cm x width 63.5 cm x height 90.5 cm x width 78.5 cm"}],
          "dcType": [{"id": "https://id.rijksmuseum.nl/2208", "http://www.w3.org/2004/02/skos/core#prefLabel":
                      [{"@language": "en", "@value": "painting"}, {"@language": "nl", "@value": "schilderij"}]}],
          "creator": [{"id": "https://id.rijksmuseum.nl/21043300", "http://www.w3.org/2004/02/skos/core#prefLabel":
                       [{"@language": "nl", "@value": "Willem van de Velde (II)"},
                        {"@language": "en", "@value": "Willem van de Velde (II)"}]}]},
         "edmRights": "http://creativecommons.org/publicdomain/mark/1.0/",
         "isShownAt": {"id": "https://www.rijksmuseum.nl/nl/collectie/object/SK-A-1848"},
         "isShownBy": {"id": "https://iiif.micr.io/eBrWZ/full/max/0/default.jpg",
           "http://rdfs.org/sioc/services#has_service": {"id": "https://iiif.micr.io/eBrWZ"}}}
        """#
        return try object(target.isEmpty ? json : json.replacingOccurrences(of: target, with: replacement))
    }
}

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

    func testActions() async {
        let module = WallpaperModule()
        await module.configDidUpdate(WallpaperConfig(sources: ["met", "wallhaven"]))
        let ids = await module.buildActions().map(\.id.actionName)
        XCTAssertEqual(ids, [
            "search", "search.met", "search.wallhaven", "random", "random.met", "random.wallhaven", "openSourcePage",
        ])

        await module.configDidUpdate(WallpaperConfig(sources: ["met"], enabledActions: ["random", "search.met"]))
        let single = await module.provideActions(query: "", scoring: scoring).map(\.id.actionName)
        // One source needs no per-source copies.
        XCTAssertEqual(single, ["random"])

        await module.configDidUpdate(WallpaperConfig(sources: ["met", "artic"], enabledActions: ["random"]))
        let family = await module.provideActions(query: "", scoring: scoring).map(\.id.actionName)
        XCTAssertEqual(family, ["random", "random.met", "random.artic"])
    }

    func testSearchMixesSourcesAndReportsFailures() async throws {
        let (module, calls) = await makeModule(sources: ["wallhaven", "rijksmuseum", "met", "artic"], stubs: [
            .wallhaven: .results([sample(.wallhaven, "w1"), sample(.wallhaven, "w2")]),
            .rijksmuseum: .results([sample(.rijksmuseum, "r1")]),
            .met: .failure(.rateLimited(.met)),
            .artic: .failure(.blocked(.artic)),
        ])

        let options = await module.provideParameterOptions(
            for: "wallpaper", in: ActionID("wallpaper/search"), query: "storm"
        )
        // A source that blocks apps isn't reported in every mixed search.
        XCTAssertEqual(options.map(\.id), ["wallhaven:w1", "rijksmuseum:r1", "wallhaven:w2", "message:met"])
        XCTAssertEqual(options[0].iconURL?.absoluteString, "https://example.com/wallhaven/w1/thumb.jpg")

        // Its own search does.
        let artic = await module.provideParameterOptions(
            for: "wallpaper", in: ActionID("wallpaper/search.artic"), query: "storm"
        )
        XCTAssertEqual(artic.map(\.id), ["message:artic"])
        XCTAssertTrue(artic[0].label.contains("browser check"))

        // Mixed searches leave the blocked source alone for a while.
        _ = await module.provideParameterOptions(for: "wallpaper", in: ActionID("wallpaper/search"), query: "wave")
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

    func testRepeatedSearchesUseTheCacheAndShortQueriesShowFeatured() async {
        let (module, calls) = await makeModule(sources: ["wallhaven"], stubs: [
            .wallhaven: .results([sample(.wallhaven, "w1")]),
        ])
        let action = ActionID("wallpaper/search")
        _ = await module.provideParameterOptions(for: "wallpaper", in: action, query: "Storm ")
        _ = await module.provideParameterOptions(for: "wallpaper", in: action, query: "storm")
        _ = await module.provideParameterOptions(for: "wallpaper", in: action, query: "s")
        _ = await module.provideParameterOptions(for: "wallpaper", in: action, query: "")

        let queries = await calls.queries[.wallhaven]
        XCTAssertEqual(queries, ["Storm", ""])
    }

    func testListedWallpapersResolveWithoutTheSource() async throws {
        let (module, calls) = await makeModule(sources: ["met"], stubs: [.met: .results([sample(.met, "1")])])
        _ = await module.provideParameterOptions(for: "wallpaper", in: ActionID("wallpaper/search"), query: "")
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
