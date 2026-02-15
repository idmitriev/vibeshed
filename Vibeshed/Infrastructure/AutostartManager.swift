import Foundation
import ServiceManagement

@MainActor
@Observable
final class AutostartManager {
    private(set) var isEnabled: Bool = false

    init() {
        refresh()
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Log.app.error("Autostart toggle failed: \(error.localizedDescription)")
        }
        refresh()
    }
}
