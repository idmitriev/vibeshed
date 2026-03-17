#!/usr/bin/env swift
// Composites AppIcon.png onto a solid square background for web use
// The corners outside the icon shape get a matching dark fill
// Usage: swift flatten-icon.swift <input.png> <output.png>

import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("Usage: flatten-icon.swift <input.png> <output.png>")
    exit(1)
}

let inputPath = args[1]
let outputPath = args[2]

guard let sourceImage = NSImage(contentsOfFile: inputPath) else {
    print("Error: Cannot load \(inputPath)")
    exit(1)
}

let size = sourceImage.size
let result = NSImage(size: size)
result.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else {
    print("Error: No graphics context")
    exit(1)
}

let rect = CGRect(origin: .zero, size: size)

// Fill entire canvas with solid background (no transparency anywhere)
let bgColor = CGColor(red: 0.10, green: 0.08, blue: 0.22, alpha: 1.0)
ctx.setFillColor(bgColor)
ctx.fill(rect)

// Draw the icon on top
sourceImage.draw(
    in: NSRect(origin: .zero, size: size),
    from: .zero,
    operation: .sourceOver,
    fraction: 1.0
)

result.unlockFocus()

guard let tiffData = result.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:])
else {
    print("Error: Failed to create PNG")
    exit(1)
}

try pngData.write(to: URL(fileURLWithPath: outputPath))
print("Flattened \(outputPath) (\(pngData.count) bytes)")
