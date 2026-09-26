#!/usr/bin/env swift

import AppKit
import Foundation

let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Assets/pppIcon.png")
let size = 1024

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
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

// A restrained text-selection mark, with no shadows or decorative effects.
let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 176, yRadius: 176)
color(0.075, 0.094, 0.125).setFill()
tile.fill()

let ink = color(0.94, 0.96, 0.98)
func bar(x: CGFloat, y: CGFloat, width: CGFloat) {
    ink.setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: 56), xRadius: 8, yRadius: 8).fill()
}

bar(x: 270, y: 654, width: 474)

// The highlighted middle line reads as selected text even at small icon sizes.
color(0.22, 0.47, 0.94).setFill()
NSBezierPath(roundedRect: NSRect(x: 250, y: 466, width: 434, height: 134), xRadius: 12, yRadius: 12).fill()
bar(x: 284, y: 505, width: 352)
bar(x: 711, y: 505, width: 58)

bar(x: 270, y: 312, width: 346)

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
