import AppKit

/// The levels Vibeshed's own windows sit at, bottom to top, kept together so the stacking
/// between them is explicit (`WindowLevelTests` pins it). Ordering a window front only
/// raises it within its level, so two of them that must never cross can't share one.
extension NSWindow.Level {
    /// The focus border: above other apps' ordinary windows, so one overlapping the focused
    /// window can't cover its ring, and below the picker. It's ordered front whenever it
    /// reappears, which at the picker's level drew it over the open picker.
    static let focusBorder = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
    /// The picker, without an overlay.
    static let picker = NSWindow.Level.floating
    /// The overlay backdrop: above the menu bar and Dock, so it covers the whole screen.
    static let pickerOverlay = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
    /// The picker while an overlay is up.
    static let pickerAboveOverlay = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
    /// The keystroke visualizer: above everything, the picker and its overlay included.
    static let keystrokeVisualizer = NSWindow.Level.screenSaver
}
