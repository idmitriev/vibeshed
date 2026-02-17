import Foundation

struct ChromiumProfile: Sendable {
    let directoryName: String
    let displayName: String
}

enum ChromiumProfileDiscovery {
    private static let appSupportDirs: [String: String] = [
        "com.google.Chrome": "Google/Chrome",
        "com.brave.Browser": "BraveSoftware/Brave-Browser",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.vivaldi.Vivaldi": "Vivaldi",
        "com.operasoftware.Opera": "com.operasoftware.Opera",
    ]

    static func discoverProfiles(bundleID: String) -> [ChromiumProfile] {
        guard let dirName = appSupportDirs[bundleID] else { return [] }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let localStatePath = home
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(dirName)
            .appendingPathComponent("Local State")

        guard let data = try? Data(contentsOf: localStatePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profileInfo = json["profile"] as? [String: Any],
              let infoCache = profileInfo["info_cache"] as? [String: Any]
        else {
            return []
        }

        return infoCache.compactMap { dirName, value -> ChromiumProfile? in
            guard let profileDict = value as? [String: Any],
                  let name = profileDict["name"] as? String
            else { return nil }
            return ChromiumProfile(directoryName: dirName, displayName: name)
        }
        .sorted { $0.directoryName < $1.directoryName }
    }
}
