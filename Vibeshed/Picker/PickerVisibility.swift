import SwiftUI

private struct PickerVisibilityKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether the picker panel is on screen. Escape hides the panel but keeps its views,
    /// and their state, for the next show — so a list row or preview that polls or
    /// redraws on a timer should pause while this is false.
    var isPickerVisible: Bool {
        get { self[PickerVisibilityKey.self] }
        set { self[PickerVisibilityKey.self] = newValue }
    }
}
