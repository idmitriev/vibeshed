#!/usr/bin/env swift
// Reads an icon PNG and writes a copy with the four corner regions made
// transparent by clipping to a rounded-square (~Apple icon shape).
// Usage: swift transparent-icon.swift <input.png> <output.png>

import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("Usage: transparent-icon.swift <input.png> <output.png>")
    exit(1)
}

guard
    let src = NSImage(contentsOfFile: args[1]),
    let tiff = src.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff)
else {
    print("Error: cannot load \(args[1])")
    exit(1)
}

let pxW = bitmap.pixelsWide
let pxH = bitmap.pixelsHigh
let size = CGSize(width: pxW, height: pxH)

// Apple-ish icon corner radius: ~22.37% of the side
let cornerRadius = CGFloat(min(pxW, pxH)) * 0.2237

guard
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
    let ctx = CGContext(
        data: nil,
        width: pxW,
        height: pxH,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
else {
    print("Error: failed to create CGContext")
    exit(1)
}

let rect = CGRect(origin: .zero, size: size)
let clipPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
ctx.addPath(clipPath)
ctx.clip()

guard let cgSrc = bitmap.cgImage else {
    print("Error: cannot get CGImage from bitmap")
    exit(1)
}
ctx.draw(cgSrc, in: rect)

guard let outCG = ctx.makeImage() else {
    print("Error: failed to render clipped image")
    exit(1)
}
let outRep = NSBitmapImageRep(cgImage: outCG)
outRep.size = size
guard let pngData = outRep.representation(using: .png, properties: [:]) else {
    print("Error: failed to encode PNG")
    exit(1)
}

try pngData.write(to: URL(fileURLWithPath: args[2]))
print("Wrote \(args[2]) (\(pngData.count) bytes, \(pxW)x\(pxH))")
