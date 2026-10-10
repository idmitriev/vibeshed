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
