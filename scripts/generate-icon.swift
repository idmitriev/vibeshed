#!/usr/bin/env swift
// Generates AppIcon.png — a 1024x1024 app icon for Vibeshed
// Dark gradient background with a stylized sparkle motif

import AppKit
import CoreGraphics

let size = 1024
let rect = NSRect(x: 0, y: 0, width: size, height: size)

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

guard let context = NSGraphicsContext.current?.cgContext else {
    fatalError("No graphics context")
}

// --- Rounded rect background with gradient ---
let cornerRadius: CGFloat = 220 // macOS icon corner radius at 1024
let bgPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

context.addPath(bgPath)
context.clip()

// Dark purple → deep blue gradient
let colorSpace = CGColorSpaceCreateDeviceRGB()
let colors = [
    CGColor(red: 0.22, green: 0.08, blue: 0.45, alpha: 1.0), // deep purple
    CGColor(red: 0.10, green: 0.12, blue: 0.38, alpha: 1.0), // dark navy
    CGColor(red: 0.06, green: 0.08, blue: 0.28, alpha: 1.0), // deeper navy
] as CFArray
let locations: [CGFloat] = [0.0, 0.6, 1.0]
if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: CGFloat(size)),
        end: CGPoint(x: CGFloat(size), y: 0),
        options: []
    )
}

// --- Subtle radial glow in center ---
let glowColors = [
    CGColor(red: 0.45, green: 0.25, blue: 0.75, alpha: 0.3),
    CGColor(red: 0.45, green: 0.25, blue: 0.75, alpha: 0.0),
] as CFArray
let glowLocations: [CGFloat] = [0.0, 1.0]
if let glowGradient = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: glowLocations) {
    let center = CGPoint(x: CGFloat(size) * 0.5, y: CGFloat(size) * 0.55)
    context.drawRadialGradient(
        glowGradient,
        startCenter: center, startRadius: 0,
        endCenter: center, endRadius: CGFloat(size) * 0.45,
        options: []
    )
}

// --- Helper: draw a 4-point sparkle ---
func drawSparkle(
    center: CGPoint, outerRadius: CGFloat, innerRadius: CGFloat,
    color: CGColor, rotation: CGFloat = 0
) {
    context.saveGState()
    context.translateBy(x: center.x, y: center.y)
    context.rotate(by: rotation)

    let path = CGMutablePath()
    // 4-pointed star: alternating outer and inner points
    for i in 0 ..< 8 {
        let angle = CGFloat(i) * .pi / 4 - .pi / 2
        let r = i % 2 == 0 ? outerRadius : innerRadius
        let pt = CGPoint(x: r * cos(angle), y: r * sin(angle))
        if i == 0 {
            path.move(to: pt)
        } else {
            path.addLine(to: pt)
        }
    }
    path.closeSubpath()

    context.setFillColor(color)
    context.addPath(path)
    context.fillPath()

    context.restoreGState()
}

// --- Main sparkle (large, center) ---
let mainCenter = CGPoint(x: CGFloat(size) * 0.5, y: CGFloat(size) * 0.52)
drawSparkle(
    center: mainCenter,
    outerRadius: 260,
    innerRadius: 55,
    color: CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.95),
    rotation: .pi / 8
)

// Inner glow on main sparkle
drawSparkle(
    center: mainCenter,
    outerRadius: 200,
    innerRadius: 45,
    color: CGColor(red: 0.75, green: 0.82, blue: 1.0, alpha: 0.6),
    rotation: .pi / 8
)

// --- Secondary sparkle (upper right, smaller) ---
drawSparkle(
    center: CGPoint(x: CGFloat(size) * 0.73, y: CGFloat(size) * 0.78),
    outerRadius: 80,
    innerRadius: 18,
    color: CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.7),
    rotation: .pi / 6
)

// --- Tertiary sparkle (lower left, smallest) ---
drawSparkle(
    center: CGPoint(x: CGFloat(size) * 0.28, y: CGFloat(size) * 0.28),
    outerRadius: 50,
    innerRadius: 12,
    color: CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.5),
    rotation: .pi / 10
)

// --- Tiny accent dots ---
let dots: [(CGPoint, CGFloat, CGFloat)] = [
    (CGPoint(x: 180, y: 700), 8, 0.4),
    (CGPoint(x: 820, y: 350), 6, 0.35),
    (CGPoint(x: 650, y: 850), 7, 0.3),
    (CGPoint(x: 380, y: 180), 5, 0.25),
]
for (pt, radius, alpha) in dots {
    context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: alpha))
    context.fillEllipse(in: CGRect(x: pt.x - radius, y: pt.y - radius, width: radius * 2, height: radius * 2))
}

image.unlockFocus()

// --- Export as PNG ---
guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fatalError("Failed to create PNG")
}

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/AppIcon.png"

try pngData.write(to: URL(fileURLWithPath: outputPath))
print("Generated \(outputPath) (\(pngData.count) bytes)")
