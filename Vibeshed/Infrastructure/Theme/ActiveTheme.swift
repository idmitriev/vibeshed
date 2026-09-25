import Foundation
import SwiftUI

/// A theme as the rest of the app sees it once applied: enough to tint Vibeshed's own UI
/// and to mark the current theme in lists.
struct ActiveThemeInfo: Codable, Sendable, Equatable {
    let name: String
    let slug: String
    let palette: ThemePalette
}

/// Which palette Vibeshed's own UI (picker, tiling focus border) follows.
///
/// The Theme module writes it — `commit` on apply (persisted, so the picker comes up
/// themed on the next launch before any module loads), `preview` while the user arrows
/// through `theme/switch` so the picker retints live. Views read `displayed`.
@MainActor
@Observable
final class ActiveTheme {
    static let shared = ActiveTheme()

    private static let defaultsKey = "theme.active"

    /// The last applied theme.
    private(set) var committed: ActiveThemeInfo?
    /// A theme being live-previewed; overrides `committed` for display until cleared.
    private(set) var previewing: ActiveThemeInfo?

    var displayed: ActiveThemeInfo? {
        previewing ?? committed
    }

    private init() {
        committed = Self.loadPersisted()
    }

    func commit(_ info: ActiveThemeInfo?) {
        withAnimation(.easeInOut(duration: 0.35)) {
            committed = info
            previewing = nil
        }
        persist(info)
    }

    func preview(_ info: ActiveThemeInfo?) {
        guard info != previewing else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            previewing = info
        }
    }

    private func persist(_ info: ActiveThemeInfo?) {
        guard let info, let data = try? JSONEncoder().encode(info) else {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
            return
        }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private static func loadPersisted() -> ActiveThemeInfo? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(ActiveThemeInfo.self, from: data)
    }
}
