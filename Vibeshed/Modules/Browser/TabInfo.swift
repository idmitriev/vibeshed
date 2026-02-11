import Foundation

struct TabInfo: Sendable, Identifiable, Equatable {
    /// Composite ID: "{bundleID}:{windowIndex}:{tabIndex}"
    let id: String
    let title: String
    let url: String
    let windowIndex: Int
    let tabIndex: Int
    let browserBundleID: String
    let browserName: String

    var domain: String {
        URL(string: url)?.host ?? url
    }

    var displayLabel: String {
        title.isEmpty ? domain : title
    }

    var displaySubtitle: String {
        "\(browserName) · \(domain)"
    }
}
