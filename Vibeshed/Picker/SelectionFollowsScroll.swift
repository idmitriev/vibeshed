import SwiftUI

/// Keeps a scrolling list's selection inside its viewport. Selection changes already
/// scroll the list (`ScrollViewReader.scrollTo`); this covers the other direction —
/// mouse-wheel, trackpad, or native page scrolling that would otherwise carry the
/// selected row out of sight. When that happens the selection moves to the nearest
/// fully visible row.
///
/// Driven by the content's offset rather than the selected row's own geometry: a fast
/// wheel flick can carry the selected row far enough in one frame that the lazy stack
/// unloads it before it reports, while the content container always reports. Rows are
/// assumed to share one height, so the selected row's frame follows from its index.
///
/// Reference type held in `@State` so per-frame geometry reports don't invalidate the body.
@MainActor
final class SelectionScrollTracker<ID: Hashable> {
    /// Tolerance for rows that `scrollTo` parks flush against a viewport edge.
    private nonisolated static var edgeSlack: CGFloat { 2 }

    /// The viewport's visible band in the scroll view's coordinate space; the top sits
    /// below whatever overlays the list (the search bar).
    var visibleTop: CGFloat = 0
    var viewportHeight: CGFloat = 0
    /// Selections this tracker made itself; the list must not `scrollTo` them, or the
    /// correction would fight an ongoing (momentum) scroll. A set because several
    /// corrections can land before SwiftUI delivers their `onChange`.
    private var scrollDrivenSelections: Set<ID> = []
    /// The most recent correction. SwiftUI may coalesce several corrections into one
    /// `onChange` carrying only this one; its delivery supersedes all earlier ones.
    private var latestScrollDrivenSelection: ID?
    /// A selection whose `scrollTo` hasn't been applied yet. Starts true: a list
    /// can appear with its selection already set (e.g. options loaded async, opening on
    /// the current value), which `onChange` never sees — the list scrolls there on appear.
    private var awaitingScrollTo = true

    /// Call from `onChange` of the selection. Returns true when the list should
    /// `scrollTo` the new selection (it came from the keyboard or a click).
    func selectionChanged(to id: ID) -> Bool {
        if scrollDrivenSelections.contains(id) {
            if id == latestScrollDrivenSelection {
                scrollDrivenSelections = []
                latestScrollDrivenSelection = nil
            } else {
                scrollDrivenSelections.remove(id)
            }
            return false
        }
        scrollDrivenSelections = []
        latestScrollDrivenSelection = nil
        scrollToStarting()
        return true
    }

    /// Call before any programmatic `scrollTo` that isn't triggered by a selection
    /// change (on appear, list reset); pair it with `scrollToApplied()`.
    func scrollToStarting() {
        awaitingScrollTo = true
    }

    /// Call once the pending `scrollTo` (on appear, or for a keyboard/click selection)
    /// has been applied.
    func scrollToApplied() {
        awaitingScrollTo = false
    }

    /// Handles a move of the list content (`contentMinY` is the top of the first row
    /// in the scroll view's coordinate space) and returns the ID that should be
    /// selected instead, if any.
    func contentMoved(
        contentMinY: CGFloat,
        selectedID: ID?,
        ids: [ID],
        rowHeight: CGFloat,
        rowSpacing: CGFloat
    ) -> ID? {
        // Mid-`scrollTo` the row may still be out of view; that isn't a user scroll. A
        // list's first layout also jumps between the top and the `scrollTo` target, so
        // in-view reports don't end the wait either — only `scrollToApplied()` does.
        guard !awaitingScrollTo, viewportHeight > visibleTop,
              let selectedID, let index = ids.firstIndex(of: selectedID)
        else { return nil }
        let pitch = rowHeight + rowSpacing
        let frame = CGRect(x: 0, y: contentMinY + CGFloat(index) * pitch, width: 0, height: rowHeight)
        let target = Self.correctedIndex(
            selectedIndex: index,
            selectedFrame: frame,
            rowPitch: pitch,
            visible: visibleTop ... viewportHeight,
            count: ids.count
        )
        guard let target, target != index else { return nil }
        let newID = ids[target]
        scrollDrivenSelections.insert(newID)
        latestScrollDrivenSelection = newID
        return newID
    }

    /// Index of the nearest row fully inside `visible`, or nil when the selected row
    /// already is. Rows are assumed to share one height, spaced `rowPitch` apart.
    nonisolated static func correctedIndex(
        selectedIndex: Int,
        selectedFrame: CGRect,
        rowPitch: CGFloat,
        visible: ClosedRange<CGFloat>,
        count: Int
    ) -> Int? {
        guard count > 0, rowPitch > 0,
              visible.upperBound - visible.lowerBound >= selectedFrame.height
        else { return nil }
        let top = visible.lowerBound - edgeSlack
        let bottom = visible.upperBound + edgeSlack
        if selectedFrame.minY < top {
            let rows = Int(((top - selectedFrame.minY) / rowPitch).rounded(.up))
            return min(count - 1, selectedIndex + rows)
        }
        if selectedFrame.maxY > bottom {
            let rows = Int(((selectedFrame.maxY - bottom) / rowPitch).rounded(.up))
            return max(0, selectedIndex - rows)
        }
        return nil
    }
}

extension View {
    /// Reports this view's top edge in `coordinateSpace` — attach to the list's row stack.
    func reportsContentOffset(in coordinateSpace: String, action: @escaping (CGFloat) -> Void) -> some View {
        onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .named(coordinateSpace)).minY
        } action: { minY in
            action(minY)
        }
    }
}
