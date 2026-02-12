import Foundation

struct FavouritesConfig: Codable, Sendable, Equatable {
    var favourites: [FavouriteEntry] = []
}

struct FavouriteEntry: Codable, Sendable, Equatable {
    let alias: String
    let action: String
    var parameters: [String: String]?
    var keywords: [String]?
    var icon: String?
    var subtitle: String?
}
