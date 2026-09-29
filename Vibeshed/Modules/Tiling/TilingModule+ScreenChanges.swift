import CoreGraphics

/// Re-fits grid-managed windows when a display's usable area changes (menu bar or Dock
/// auto-hide toggled, display reconfigured).
extension TilingModule {
    /// Puts every window that has a grid assignment back into its slot, measured against the
    /// display's current usable area: a cell stretches into the space a hidden menu bar or Dock
    /// frees, and shrinks back when it returns. Runs whether or not auto-tile is on — an
    /// attached window stays attached. Windows moved to another display since being assigned,
    /// or closed, are left alone.
    func relayoutAssignedWindows() async {
        guard !assignments.isEmpty else { return }
        let mgr = manager
        let cfg = config
        let windows = await MainActor.run { mgr.listWindows(includeMinimized: false) }
        let displays = await MainActor.run { mgr.windowsByDisplay(windows, config: cfg) }

        var moved = 0
        for display in displays {
            for window in display.windows {
                guard let assignment = assignments[window.id],
                      assignment.displayKey == display.grid.displayKey
                else { continue }
                let target = Self.frame(for: assignment.slot, in: display.grid)
                guard !Self.isSameFrame(window.frame, target) else { continue }
                do {
                    try mgr.setFrame(window, frame: target)
                    moved += 1
                } catch {
                    log.error("relayout: failed to set frame for window \(window.id, privacy: .public)")
                }
            }
        }
        log.info("Screen area changed: re-fitted \(moved, privacy: .public) window(s)")

        // Our own moves must not read as user drags on the next auto-tile poll.
        let current = await MainActor.run { mgr.listWindows(includeMinimized: false) }
        lastKnownFrames = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0.frame) })
    }

    private static func frame(for slot: AutoTileLayout.Slot, in resolved: ResolvedGrid) -> CGRect {
        switch slot {
        case .maximized:
            resolved.area
        case let .cell(row, col):
            TilingGrid.cellRect(row: row, col: col, in: resolved.area, grid: resolved.grid, gap: resolved.gap)
        }
    }

    private static func isSameFrame(_ lhs: CGRect, _ rhs: CGRect, tolerance: Double = 1.0) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
    }
}
