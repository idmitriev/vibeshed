import AppKit

/// Split-navigation actions: parameterized detach, swap with the next split, and
/// focus next/previous split (with a recently-focused fallback off-grid). Split
/// scanning lives in `TilingSplits`.
extension TilingModule {
    func makeDetachWindowAction() -> TilingAction {
        TilingAction(
            id: ActionID(module: "tiling", name: "detachWindow"),
            title: "Detach a Window from Grid",
            subtitle: "Choose a tiled window to stop grid-managing",
            iconName: "square.dashed.inset.filled",
            keywords: ["tiling", "grid", "detach", "float", "release", "remove", "window"],
            parameters: [
                ActionParameter(
                    id: "window",
                    label: "Window",
                    type: .dynamicSelection(hint: "window"),
                    isRequired: true
                ),
            ]
        ) { [weak self] values in
            guard let idString = values["window"], let windowID = Int(idString) else {
                return .showResult(title: "Error", body: "No window selected")
            }
            await self?.removeAssignment(windowID: windowID)
            return .dismiss
        }
    }

    func makeSwapNextSplitAction(mgr: TilingManager, cfg: TilingConfig) -> TilingAction {
        TilingAction(
            id: ActionID(module: "tiling", name: "swapNextSplit"),
            title: "Swap Window with Next Split",
            subtitle: "Swap the focused window with the visible window in the next grid split",
            iconName: "rectangle.2.swap",
            keywords: ["tiling", "grid", "swap", "split", "exchange", "window"]
        ) { [weak self] _ in
            guard let scan = await MainActor.run(body: {
                TilingSplits.scan(manager: mgr, config: cfg)
            }) else {
                return .showResult(title: "No Grid", body: "No focused window or no grid on this display")
            }
            guard let target = TilingSplits.occupiedSplit(in: scan, step: 1) else {
                return .showResult(title: "No Other Split", body: "No other occupied split to swap with")
            }
            try mgr.setFrame(scan.focused, frame: TilingSplits.cellRect(at: target.cellIndex, in: scan))
            try mgr.setFrame(target.window, frame: TilingSplits.cellRect(at: scan.currentCellIndex, in: scan))
            let focusedCell = TilingSplits.cell(at: target.cellIndex, in: scan)
            let targetCell = TilingSplits.cell(at: scan.currentCellIndex, in: scan)
            await self?.setAssignment(
                windowID: scan.focused.id, displayKey: scan.displayKey,
                row: focusedCell.row, col: focusedCell.col
            )
            await self?.setAssignment(
                windowID: target.window.id, displayKey: scan.displayKey,
                row: targetCell.row, col: targetCell.col
            )
            return .dismiss
        }
    }

    func makeFocusSplitAction(forward: Bool, mgr: TilingManager, cfg: TilingConfig) -> TilingAction {
        let (name, title, direction) = forward
            ? ("focusNextSplit", "Focus Next Split", "next")
            : ("focusPreviousSplit", "Focus Previous Split", "previous")
        return TilingAction(
            id: ActionID(module: "tiling", name: name),
            title: title,
            subtitle: "Focus the visible window in the \(direction) split, "
                + "or the \(direction) recently focused window off-grid",
            iconName: forward ? "arrow.forward.square" : "arrow.backward.square",
            keywords: ["tiling", "grid", "focus", "split", direction, "window", "cycle"]
        ) { _ in
            // Split navigation when the focused window sits on a grid with another
            // occupied split; otherwise cycle the recently-focused (z-order) queue.
            if let scan = await MainActor.run(body: {
                TilingSplits.scan(manager: mgr, config: cfg)
            }),
                let target = TilingSplits.occupiedSplit(in: scan, step: forward ? 1 : -1)
            {
                try mgr.focusWindow(target.window)
                return .dismiss
            }
            return try await TilingSplits.focusRecentWindow(manager: mgr, forward: forward)
        }
    }
}
