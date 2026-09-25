import Foundation

/// iTerm's profile preferences, as far as the theme needs them: which profile is the
/// default, and handing that role to the "Vibeshed" Dynamic Profile (and back).
///
/// Colors set on sessions over AppleScript die with the session, so on its own the theme
/// wouldn't survive an iTerm restart. Making the Vibeshed profile the default — while it
/// inherits everything but colors from the user's own default — does.
enum ITermProfiles {
    static let domain = "com.googlecode.iterm2"
    private static let defaultKey = "Default Bookmark Guid"
    private static let profilesKey = "New Bookmarks"
    /// Vibeshed's own defaults: the user's default profile before Vibeshed took over.
    private static let previousDefaultKey = "theme.iterm.previousDefaultProfile"

    private struct Profile {
        let guid: String
        let name: String
    }

    /// The profile the Vibeshed profile inherits fonts, keys, etc. from: the user's own
    /// default (remembered once Vibeshed's profile has become the default).
    static func parentProfileName() -> String? {
        if let current = currentDefault(), current.guid != ITermTarget.profileGUID {
            return current.name
        }
        return previousDefault()?.name
    }

    /// Makes the Vibeshed profile iTerm's default (`adopt`), or hands the role back to the
    /// profile it took it from. Read by iTerm at launch; a running iTerm keeps using its
    /// current default for new sessions until restarted.
    static func setVibeshedDefault(_ adopt: Bool) {
        let current = currentDefault()
        if adopt {
            guard current?.guid != ITermTarget.profileGUID else { return }
            if let current {
                UserDefaults.standard.set(["guid": current.guid, "name": current.name], forKey: previousDefaultKey)
            }
            SystemPreferences.set(ITermTarget.profileGUID, forKey: defaultKey, domain: domain)
        } else if current?.guid == ITermTarget.profileGUID, let previous = previousDefault() {
            SystemPreferences.set(previous.guid, forKey: defaultKey, domain: domain)
            UserDefaults.standard.removeObject(forKey: previousDefaultKey)
        }
    }

    private static func currentDefault() -> Profile? {
        guard let guid = SystemPreferences.value(defaultKey, domain: domain) as? String else { return nil }
        let profiles = SystemPreferences.value(profilesKey, domain: domain) as? [[String: Any]] ?? []
        let name = profiles.first { $0["Guid"] as? String == guid }?["Name"] as? String
        return name.map { Profile(guid: guid, name: $0) } ?? (guid == ITermTarget.profileGUID
            ? Profile(guid: guid, name: "Vibeshed") : nil)
    }

    private static func previousDefault() -> Profile? {
        guard let saved = UserDefaults.standard.dictionary(forKey: previousDefaultKey) as? [String: String],
              let guid = saved["guid"], let name = saved["name"]
        else { return nil }
        return Profile(guid: guid, name: name)
    }
}
