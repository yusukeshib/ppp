#!/usr/bin/env swift

import AppKit
import Foundation

let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Assets/pppIcon.png")
let size = 1024

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Could not create icon canvas")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.shouldAntialias = true

NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()

// Flat tile on the standard macOS icon grid (824pt body inside a 1024pt canvas).
let tile = NSBezierPath(
    roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
    xRadius: 185,
    yRadius: 185
)
color(0.36, 0.33, 0.85).setFill()
tile.fill()

// A single solid speech bubble: rounded body plus a small tail at the bottom left.
// Keep in sync with Sources/ppp/StatusBarIcon.swift (menu bar icon).
let bubble = NSBezierPath(
    roundedRect: NSRect(x: 262, y: 362, width: 500, height: 340),
    xRadius: 120,
    yRadius: 120
)
let tail = NSBezierPath()
tail.move(to: NSPoint(x: 340, y: 400))
tail.line(to: NSPoint(x: 312, y: 300))
tail.line(to: NSPoint(x: 450, y: 380))
tail.close()
bubble.append(tail)

NSColor.white.setFill()
bubble.fill()

NSGraphicsContext.restoreGraphicsState()

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode icon PNG")
}
try png.write(to: outputURL)
print("Generated \(outputURL.path)")
