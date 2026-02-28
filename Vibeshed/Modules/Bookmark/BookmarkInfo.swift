import Foundation

struct BookmarkInfo: Sendable {
    let title: String
    let url: String
    let folderPath: String
    let browserBundleID: String
    let browserName: String

    var domain: String {
        URL(string: url)?.host ?? url
    }
}

struct VisitedSite: Sendable {
    let title: String
    let url: String
    let visitCount: Int
    let lastVisited: Date?
    let browserBundleID: String
    let browserName: String

    var domain: String {
        URL(string: url)?.host ?? url
    }
}
