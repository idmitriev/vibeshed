import CoreGraphics
import Foundation
import ShowreelCore

/// Synthesizes pointer input with eased motion, so a recorded cursor glides
/// instead of teleporting.
@MainActor
enum Mouse {
    private static let source = CGEventSource(stateID: .hidSystemState)
    private static let stepsPerSecond = 120.0

    static var position: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    static func warp(to point: Point) {
        let target = CGPoint(x: point.x, y: point.y)
        CGWarpMouseCursorPosition(target)
        post(.mouseMoved, at: target)
    }

    static func move(to point: Point, duration: Double, dragging: Bool = false) async throws {
        let start = position
        let end = CGPoint(x: point.x, y: point.y)
        let steps = max(1, Int(duration * stepsPerSecond))
        for step in 1 ... steps {
            let progress = easeInOut(Double(step) / Double(steps))
            let location = CGPoint(
                x: start.x + (end.x - start.x) * progress,
                y: start.y + (end.y - start.y) * progress
            )
            post(dragging ? .leftMouseDragged : .mouseMoved, at: location)
            if step < steps {
                try await Task.sleep(for: .seconds(1 / stepsPerSecond))
            }
        }
    }

    static func click(_ click: Click) async throws {
        if let target = click.at {
            if click.glide > 0 {
                try await move(to: target, duration: click.glide)
                try await Task.sleep(for: .milliseconds(80))
            } else {
                warp(to: target)
            }
        }
        let (down, up): (CGEventType, CGEventType) = click.button == .left
            ? (.leftMouseDown, .leftMouseUp)
            : (.rightMouseDown, .rightMouseUp)
        let button: CGMouseButton = click.button == .left ? .left : .right
        try SystemDialogs.ensureNone()
        for index in 1 ... max(1, click.count) {
            post(down, at: position, button: button, clickState: index)
            try await Task.sleep(for: .milliseconds(60))
            post(up, at: position, button: button, clickState: index)
            if index < click.count {
                try await Task.sleep(for: .milliseconds(90))
            }
        }
    }

    static func drag(_ drag: Drag) async throws {
        try await move(to: drag.from, duration: 0.3)
        try SystemDialogs.ensureNone()
        post(.leftMouseDown, at: position)
        try await Task.sleep(for: .milliseconds(120))
        try await move(to: drag.to, duration: drag.duration, dragging: true)
        try await Task.sleep(for: .milliseconds(80))
        post(.leftMouseUp, at: position)
    }

    static func scroll(_ scroll: Scroll) async throws {
        if let target = scroll.at {
            try await move(to: target, duration: 0.3)
        }
        let pixelsPerLine = 16.0
        let steps = max(1, Int(scroll.duration * 60))
        // Positive dy scrolls down the page, which is a negative wheel delta.
        let stepY = -scroll.dy * pixelsPerLine / Double(steps)
        let stepX = -scroll.dx * pixelsPerLine / Double(steps)
        for _ in 0 ..< steps {
            let event = CGEvent(
                scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                wheel1: Int32(stepY.rounded()), wheel2: Int32(stepX.rounded()), wheel3: 0
            )
            event?.post(tap: .cghidEventTap)
            try await Task.sleep(for: .seconds(1 / 60))
        }
    }

    private static func post(
        _ type: CGEventType,
        at location: CGPoint,
        button: CGMouseButton = .left,
        clickState: Int = 1
    ) {
        guard let event = CGEvent(
            mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: button
        ) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
        event.post(tap: .cghidEventTap)
    }

    private static func easeInOut(_ progress: Double) -> Double {
        progress < 0.5 ? 4 * progress * progress * progress : 1 - pow(-2 * progress + 2, 3) / 2
    }
}
