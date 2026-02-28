import Foundation
import OSLog
import SQLite3

private let log = Log.module("bookmark")

enum BookmarkManager {
    // MARK: - Bookmarks

    static func readBookmarks(
        browsers: [(name: String, bundleID: String)]
    ) -> [BookmarkInfo] {
        var all: [BookmarkInfo] = []
        for browser in browsers {
            let entry = BrowserRegistry.entry(for: browser.bundleID)
            if browser.bundleID == "com.apple.Safari" {
                all.append(contentsOf: readSafariBookmarks(browserName: browser.name))
            } else if entry?.isChromium == true {
                let profiles = chromiumProfiles(bundleID: browser.bundleID)
                for profile in profiles {
                    all.append(
                        contentsOf: readChromiumBookmarks(
                            bundleID: browser.bundleID,
                            browserName: browser.name,
                            profileDir: profile
                        )
                    )
                }
            }
        }
        return all
    }

    // MARK: - Most Visited

    static func readMostVisited(
        browsers: [(name: String, bundleID: String)],
        minVisitCount: Int
    ) -> [VisitedSite] {
        var all: [VisitedSite] = []
        for browser in browsers {
            let entry = BrowserRegistry.entry(for: browser.bundleID)
            if browser.bundleID == "com.apple.Safari" {
                all.append(
                    contentsOf: readSafariHistory(
                        browserName: browser.name,
                        minVisitCount: minVisitCount
                    )
                )
            } else if entry?.isChromium == true {
                let profiles = chromiumProfiles(bundleID: browser.bundleID)
                for profile in profiles {
                    all.append(
                        contentsOf: readChromiumHistory(
                            bundleID: browser.bundleID,
                            browserName: browser.name,
                            profileDir: profile,
                            minVisitCount: minVisitCount
                        )
                    )
                }
            }
        }
        // Deduplicate by URL, keeping the one with the highest visit count
        var bestByURL: [String: VisitedSite] = [:]
        for site in all {
            if let existing = bestByURL[site.url] {
                if site.visitCount > existing.visitCount {
                    bestByURL[site.url] = site
                }
            } else {
                bestByURL[site.url] = site
            }
        }
        return bestByURL.values.sorted { $0.visitCount > $1.visitCount }
    }

    // MARK: - Safari Bookmarks

    private static func readSafariBookmarks(browserName: String) -> [BookmarkInfo] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let path = home.appendingPathComponent("Library/Safari/Bookmarks.plist").path

        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil
              ) as? [String: Any]
        else {
            log.debug("Cannot read Safari bookmarks at \(path, privacy: .public)")
            return []
        }

        var bookmarks: [BookmarkInfo] = []
        parseSafariBookmarkNode(plist, folderPath: "", into: &bookmarks, browserName: browserName)
        return bookmarks
    }

    private static func parseSafariBookmarkNode(
        _ node: [String: Any],
        folderPath: String,
        into bookmarks: inout [BookmarkInfo],
        browserName: String
    ) {
        let type = node["WebBookmarkType"] as? String

        if type == "WebBookmarkTypeLeaf" {
            if let uriDict = node["URIDictionary"] as? [String: Any],
               let title = uriDict["title"] as? String,
               let url = node["URLString"] as? String,
               !url.isEmpty
            {
                bookmarks.append(BookmarkInfo(
                    title: title,
                    url: url,
                    folderPath: folderPath,
                    browserBundleID: "com.apple.Safari",
                    browserName: browserName
                ))
            }
            return
        }

        if let children = node["Children"] as? [[String: Any]] {
            let folderTitle = node["Title"] as? String ?? ""
            let nextPath: String
            if folderTitle.isEmpty || folderTitle == "BookmarksBar" || folderTitle == "BookmarksMenu" {
                let displayName = folderTitle == "BookmarksBar" ? "Bookmarks Bar"
                    : folderTitle == "BookmarksMenu" ? "Bookmarks Menu" : ""
                nextPath = folderPath.isEmpty ? displayName : folderPath
            } else {
                nextPath = folderPath.isEmpty ? folderTitle : "\(folderPath) / \(folderTitle)"
            }
            for child in children {
                parseSafariBookmarkNode(child, folderPath: nextPath, into: &bookmarks, browserName: browserName)
            }
        }
    }

    // MARK: - Chromium Bookmarks

    private static func readChromiumBookmarks(
        bundleID: String,
        browserName: String,
        profileDir: String
    ) -> [BookmarkInfo] {
        guard let appSupportDir = chromiumAppSupportDir(bundleID: bundleID) else { return [] }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let bookmarksPath = home
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(appSupportDir)
            .appendingPathComponent(profileDir)
            .appendingPathComponent("Bookmarks")
            .path

        guard FileManager.default.fileExists(atPath: bookmarksPath),
              let data = FileManager.default.contents(atPath: bookmarksPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = json["roots"] as? [String: Any]
        else {
            log.debug("Cannot read Chromium bookmarks at \(bookmarksPath, privacy: .public)")
            return []
        }

        var bookmarks: [BookmarkInfo] = []
        for (_, value) in roots {
            guard let node = value as? [String: Any] else { continue }
            parseChromiumBookmarkNode(
                node,
                folderPath: "",
                into: &bookmarks,
                bundleID: bundleID,
                browserName: browserName
            )
        }
        return bookmarks
    }

    private static func parseChromiumBookmarkNode(
        _ node: [String: Any],
        folderPath: String,
        into bookmarks: inout [BookmarkInfo],
        bundleID: String,
        browserName: String
    ) {
        let type = node["type"] as? String

        if type == "url" {
            if let name = node["name"] as? String,
               let url = node["url"] as? String,
               !url.isEmpty
            {
                bookmarks.append(BookmarkInfo(
                    title: name,
                    url: url,
                    folderPath: folderPath,
                    browserBundleID: bundleID,
                    browserName: browserName
                ))
            }
            return
        }

        if type == "folder", let children = node["children"] as? [[String: Any]] {
            let folderName = node["name"] as? String ?? ""
            let nextPath = folderPath.isEmpty ? folderName : "\(folderPath) / \(folderName)"
            for child in children {
                parseChromiumBookmarkNode(
                    child,
                    folderPath: nextPath,
                    into: &bookmarks,
                    bundleID: bundleID,
                    browserName: browserName
                )
            }
        }
    }

    // MARK: - Safari History

    private static func readSafariHistory(
        browserName: String,
        minVisitCount: Int
    ) -> [VisitedSite] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dbPath = home.appendingPathComponent("Library/Safari/History.db").path

        guard FileManager.default.fileExists(atPath: dbPath) else {
            log.debug("Safari History.db not found")
            return []
        }

        // Safari locks the DB while running; use READONLY + immutable to avoid WAL issues
        let uri = "file:\(dbPath)?immutable=1"
        var db: OpaquePointer?
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            log.debug("Cannot open Safari History.db")
            return []
        }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT h.url, v.title, h.visit_count
            FROM history_items h
            JOIN history_visits v ON h.id = v.history_item
            WHERE h.visit_count >= ?1
            GROUP BY h.url
            ORDER BY h.visit_count DESC
            LIMIT 500
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            log.debug("Safari History.db prepare failed")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(minVisitCount))

        var results: [VisitedSite] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let urlPtr = sqlite3_column_text(stmt, 0) else { continue }
            let url = String(cString: urlPtr)
            let title: String
            if let titlePtr = sqlite3_column_text(stmt, 1) {
                title = String(cString: titlePtr)
            } else {
                title = url
            }
            let visitCount = Int(sqlite3_column_int(stmt, 2))

            results.append(VisitedSite(
                title: title.isEmpty ? url : title,
                url: url,
                visitCount: visitCount,
                lastVisited: nil,
                browserBundleID: "com.apple.Safari",
                browserName: browserName
            ))
        }
        return results
    }

    // MARK: - Chromium History

    private static func readChromiumHistory(
        bundleID: String,
        browserName: String,
        profileDir: String,
        minVisitCount: Int
    ) -> [VisitedSite] {
        guard let appSupportDir = chromiumAppSupportDir(bundleID: bundleID) else { return [] }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let dbPath = home
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(appSupportDir)
            .appendingPathComponent(profileDir)
            .appendingPathComponent("History")
            .path

        guard FileManager.default.fileExists(atPath: dbPath) else {
            log.debug("Chromium History not found at \(dbPath, privacy: .public)")
            return []
        }

        // Use immutable mode to avoid locking issues with running browser
        let uri = "file:\(dbPath)?immutable=1"
        var db: OpaquePointer?
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            log.debug("Cannot open Chromium History at \(dbPath, privacy: .public)")
            return []
        }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT url, title, visit_count, last_visit_time
            FROM urls
            WHERE visit_count >= ?1 AND hidden = 0
            ORDER BY visit_count DESC
            LIMIT 500
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            log.debug("Chromium History prepare failed")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(minVisitCount))

        var results: [VisitedSite] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let urlPtr = sqlite3_column_text(stmt, 0) else { continue }
            let url = String(cString: urlPtr)
            let title: String
            if let titlePtr = sqlite3_column_text(stmt, 1) {
                title = String(cString: titlePtr)
            } else {
                title = url
            }
            let visitCount = Int(sqlite3_column_int(stmt, 2))

            // Chrome timestamps: microseconds since 1601-01-01
            let chromeTime = sqlite3_column_int64(stmt, 3)
            let lastVisited: Date?
            if chromeTime > 0 {
                let unixSeconds = Double(chromeTime) / 1_000_000.0 - 11_644_473_600.0
                lastVisited = Date(timeIntervalSince1970: unixSeconds)
            } else {
                lastVisited = nil
            }

            results.append(VisitedSite(
                title: title.isEmpty ? url : title,
                url: url,
                visitCount: visitCount,
                lastVisited: lastVisited,
                browserBundleID: bundleID,
                browserName: browserName
            ))
        }
        return results
    }

    // MARK: - Helpers

    private static let chromiumDirs: [String: String] = [
        "com.google.Chrome": "Google/Chrome",
        "com.brave.Browser": "BraveSoftware/Brave-Browser",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.vivaldi.Vivaldi": "Vivaldi",
        "com.operasoftware.Opera": "com.operasoftware.Opera",
    ]

    private static func chromiumAppSupportDir(bundleID: String) -> String? {
        chromiumDirs[bundleID]
    }

    private static func chromiumProfiles(bundleID: String) -> [String] {
        let profiles = ChromiumProfileDiscovery.discoverProfiles(bundleID: bundleID)
        if profiles.isEmpty {
            return ["Default"]
        }
        return profiles.map(\.directoryName)
    }
}
