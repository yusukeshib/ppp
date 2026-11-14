import AppKit

/// Menu bar icon: the same speech bubble as the app icon (Scripts/generate-icon.swift),
/// drawn as a template image so macOS tints it for light and dark menu bars.
enum StatusBarIcon {
    /// Bubble bounds in the 1024px app icon canvas, including the tail.
    private static let sourceBounds = NSRect(x: 262, y: 300, width: 500, height: 402)

    static func make(accessibilityDescription: String) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let scale = 16 / sourceBounds.width
            let drawnHeight = sourceBounds.height * scale
            let origin = NSPoint(x: rect.midX - 8, y: rect.midY - drawnHeight / 2)

            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(
                    x: origin.x + (x - sourceBounds.minX) * scale,
                    y: origin.y + (y - sourceBounds.minY) * scale
                )
            }

            let bodyOrigin = point(262, 362)
            let body = NSBezierPath(
                roundedRect: NSRect(x: bodyOrigin.x, y: bodyOrigin.y, width: 500 * scale, height: 340 * scale),
                xRadius: 120 * scale,
                yRadius: 120 * scale
            )
            let tail = NSBezierPath()
            tail.move(to: point(340, 400))
            tail.line(to: point(312, 300))
            tail.line(to: point(450, 380))
            tail.close()
            body.append(tail)

            NSColor.black.setFill()
            body.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }
}
