import Foundation

struct MenuConfig: Codable, Sendable, Equatable {
    /// List the frontmost app's menu items in the main search. When false they are
    /// only reachable through `menu/search`.
    var showInSearch = true
    /// Submenus with more items than this are skipped: they're content lists
    /// (Safari's per-day history, bookmark folders), not commands. Top-level menus
    /// are always read.
    var maxSubmenuItems = 100
    var cacheTTLSeconds = 3.0
    /// Apps whose menus are never listed (e.g. ones with a slow accessibility tree).
    var excludedBundleIDs: [String] = []

    init() {}

    /// Decodes each field leniently: Codable synthesis ignores Swift property
    /// defaults, and a user's section may specify only some keys.
    init(from decoder: Decoder) throws {
        let defaults = MenuConfig()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showInSearch = try container.decodeIfPresent(Bool.self, forKey: .showInSearch)
            ?? defaults.showInSearch
        maxSubmenuItems = try container.decodeIfPresent(Int.self, forKey: .maxSubmenuItems)
            ?? defaults.maxSubmenuItems
        cacheTTLSeconds = try container.decodeIfPresent(Double.self, forKey: .cacheTTLSeconds)
            ?? defaults.cacheTTLSeconds
        excludedBundleIDs = try container.decodeIfPresent([String].self, forKey: .excludedBundleIDs)
            ?? defaults.excludedBundleIDs
    }

    private enum CodingKeys: String, CodingKey {
        case showInSearch
        case maxSubmenuItems
        case cacheTTLSeconds
        case excludedBundleIDs
    }
}
