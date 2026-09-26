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

// Soft paper tile, matching the friendly hand-drawn style of the app.
let tileRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: 184, yRadius: 184)

let tileShadow = NSShadow()
tileShadow.shadowColor = color(0.18, 0.16, 0.22, alpha: 0.18)
tileShadow.shadowBlurRadius = 38
tileShadow.shadowOffset = NSSize(width: 0, height: -14)
tileShadow.set()
color(0.94, 0.93, 0.90).setFill()
tile.fill()

NSShadow().set()
let paper = NSGradient(
    starting: color(1.00, 0.995, 0.98),
    ending: color(0.94, 0.925, 0.89)
)!
paper.draw(in: tile, angle: -90)

color(0.20, 0.18, 0.25, alpha: 0.055).setStroke()
tile.lineWidth = 4
tile.stroke()

// A loose, single-stroke speech bubble. The uneven proportions keep it playful.
let bubble = NSBezierPath()
bubble.move(to: NSPoint(x: 364, y: 309))
bubble.curve(
    to: NSPoint(x: 250, y: 432),
    controlPoint1: NSPoint(x: 298, y: 315),
    controlPoint2: NSPoint(x: 250, y: 363)
)
bubble.line(to: NSPoint(x: 250, y: 566))
bubble.curve(
    to: NSPoint(x: 390, y: 713),
    controlPoint1: NSPoint(x: 250, y: 654),
    controlPoint2: NSPoint(x: 307, y: 713)
)
bubble.line(to: NSPoint(x: 645, y: 713))
bubble.curve(
    to: NSPoint(x: 785, y: 568),
    controlPoint1: NSPoint(x: 729, y: 713),
    controlPoint2: NSPoint(x: 785, y: 654)
)
bubble.line(to: NSPoint(x: 785, y: 447))
bubble.curve(
    to: NSPoint(x: 648, y: 309),
    controlPoint1: NSPoint(x: 785, y: 365),
    controlPoint2: NSPoint(x: 730, y: 309)
)
bubble.line(to: NSPoint(x: 483, y: 309))
bubble.curve(
    to: NSPoint(x: 331, y: 244),
    controlPoint1: NSPoint(x: 429, y: 309),
    controlPoint2: NSPoint(x: 383, y: 281)
)
bubble.curve(
    to: NSPoint(x: 364, y: 309),
    controlPoint1: NSPoint(x: 342, y: 270),
    controlPoint2: NSPoint(x: 354, y: 294)
)
bubble.lineWidth = 58
bubble.lineCapStyle = .round
bubble.lineJoinStyle = .round

let inkShadow = NSShadow()
inkShadow.shadowColor = color(0.30, 0.24, 0.67, alpha: 0.22)
inkShadow.shadowOffset = NSSize(width: 0, height: -8)
inkShadow.shadowBlurRadius = 20
inkShadow.set()
color(0.37, 0.32, 0.82).setStroke()
bubble.stroke()

// A tiny warm sparkle adds the AI cue without making the icon feel technical.
NSShadow().set()
let sparkle = NSBezierPath()
let sparklePoints = [
    NSPoint(x: 760, y: 828),
    NSPoint(x: 780, y: 780),
    NSPoint(x: 828, y: 760),
    NSPoint(x: 780, y: 740),
    NSPoint(x: 760, y: 692),
    NSPoint(x: 740, y: 740),
    NSPoint(x: 692, y: 760),
    NSPoint(x: 740, y: 780)
]
sparkle.move(to: sparklePoints[0])
for point in sparklePoints.dropFirst() {
    sparkle.line(to: point)
}
sparkle.close()

let sparkleShadow = NSShadow()
sparkleShadow.shadowColor = color(0.78, 0.48, 0.05, alpha: 0.24)
sparkleShadow.shadowOffset = NSSize(width: 0, height: -5)
sparkleShadow.shadowBlurRadius = 12
sparkleShadow.set()
color(1.00, 0.72, 0.20).setFill()
sparkle.fill()

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
