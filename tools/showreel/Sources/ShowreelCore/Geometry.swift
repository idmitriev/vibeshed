import Foundation

/// A point in the guest display's coordinate space: points (not pixels), with
/// the origin at the top-left of the main display. Written `[x, y]` in scenes.
public struct Point: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        x = try container.decode(Double.self)
        y = try container.decode(Double.self)
        guard container.isAtEnd else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "expected [x, y]")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
    }
}

/// A rectangle in the same space as `Point`. Written `[x, y, width, height]`.
public struct Rect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        x = try container.decode(Double.self)
        y = try container.decode(Double.self)
        width = try container.decode(Double.self)
        height = try container.decode(Double.self)
        guard container.isAtEnd else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "expected [x, y, width, height]")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
        try container.encode(width)
        try container.encode(height)
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }

    public func union(_ other: Rect) -> Rect {
        let minX = min(x, other.x)
        let minY = min(y, other.y)
        return Rect(x: minX, y: minY, width: max(maxX, other.maxX) - minX, height: max(maxY, other.maxY) - minY)
    }

    public func insetBy(_ amount: Double) -> Rect {
        Rect(x: x + amount, y: y + amount, width: width - 2 * amount, height: height - 2 * amount)
    }

    /// The part of `self` inside `bounds`.
    public func clamped(to bounds: Rect) -> Rect {
        let minX = max(x, bounds.x)
        let minY = max(y, bounds.y)
        let width = max(0, min(maxX, bounds.maxX) - minX)
        let height = max(0, min(maxY, bounds.maxY) - minY)
        return Rect(x: minX, y: minY, width: width, height: height)
    }
}

/// The size of a display mode in points, e.g. `{ width: 1440, height: 900 }`.
public struct DisplaySize: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}
