import Foundation

struct AliasEntry: Codable, Sendable, Equatable {
    let alias: String
    let action: String
    var parameters: [String: String]?
    var keywords: [String]?
    var icon: String?
    var subtitle: String?
}
