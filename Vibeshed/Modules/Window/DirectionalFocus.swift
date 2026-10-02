import CoreGraphics

/// Picks the window to focus when moving focus left, right, up or down, as tiling
/// window managers do: the nearest window on that side of the focused one.
/// Frames are in global screen coordinates with the origin at the top left, as
/// `WindowListHelper` and AX report them.
enum DirectionalFocus {
    enum Direction: String, CaseIterable, Sendable {
        case left, right, up, down
    }

    /// Smaller windows are skipped: slivers and invisible helper windows some apps keep.
    static let minimumSize: CGFloat = 50

    /// The window in `direction` from `focused`, among `windows` in front-to-back order.
    ///
    /// A candidate lies wholly past the focused window's center line on that side; when
    /// nothing does (overlapping floating windows), any window whose center is past it
    /// counts. Windows level with the focused one (overlapping it across the direction)
    /// win over ones off to a side, then the nearest edge, then the nearest center, then
    /// the frontmost, so a stack of windows in one tile gives the one on top.
    static func target(from focused: WindowInfo, direction: Direction, among windows: [WindowInfo]) -> WindowInfo? {
        let others = windows.filter { window in
            window.id != focused.id && window.frame.width >= minimumSize && window.frame.height >= minimumSize
        }
        let origin = focused.frame
        var candidates = others.filter { direction.isPastCenterLine($0.frame, of: origin) }
        if candidates.isEmpty {
            candidates = others.filter { direction.hasCenterPast($0.frame, of: origin) }
        }
        let level = candidates.filter { direction.isLevel($0.frame, with: origin) }
        let pool = level.isEmpty ? candidates : level
        return pool.enumerated().min { lhs, rhs in
            direction.rank(lhs.element.frame, from: origin, zOrder: lhs.offset)
                < direction.rank(rhs.element.frame, from: origin, zOrder: rhs.offset)
        }?.element
    }
}

extension DirectionalFocus.Direction {
    /// `frame` lies wholly on this side of `origin`'s center line.
    func isPastCenterLine(_ frame: CGRect, of origin: CGRect) -> Bool {
        switch self {
        case .left: frame.maxX <= origin.midX
        case .right: frame.minX >= origin.midX
        case .up: frame.maxY <= origin.midY
        case .down: frame.minY >= origin.midY
        }
    }

    func hasCenterPast(_ frame: CGRect, of origin: CGRect) -> Bool {
        switch self {
        case .left: frame.midX < origin.midX
        case .right: frame.midX > origin.midX
        case .up: frame.midY < origin.midY
        case .down: frame.midY > origin.midY
        }
    }

    /// `frame` overlaps `origin` across the direction: beside it, not diagonally off.
    func isLevel(_ frame: CGRect, with origin: CGRect) -> Bool {
        switch self {
        case .left, .right: min(frame.maxY, origin.maxY) > max(frame.minY, origin.minY)
        case .up, .down: min(frame.maxX, origin.maxX) > max(frame.minX, origin.minX)
        }
    }

    /// Ordering key, smallest first: the gap between the two facing edges, then how far
    /// the centers are apart across the direction, then front-to-back position. Points
    /// are rounded so frames a fraction apart tie.
    func rank(_ frame: CGRect, from origin: CGRect, zOrder: Int) -> (CGFloat, CGFloat, Int) {
        let (gap, offset): (CGFloat, CGFloat) = switch self {
        case .left: (origin.minX - frame.maxX, abs(frame.midY - origin.midY))
        case .right: (frame.minX - origin.maxX, abs(frame.midY - origin.midY))
        case .up: (origin.minY - frame.maxY, abs(frame.midX - origin.midX))
        case .down: (frame.minY - origin.maxY, abs(frame.midX - origin.midX))
        }
        return (gap.rounded(), offset.rounded(), zOrder)
    }
}
