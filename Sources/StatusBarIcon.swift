import Cocoa

enum StatusBarIcon {
    static func makeImage() -> NSImage {
        // Menu bar artwork must not depend on the app bundle's Dock icon.
        let image = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "SakuraClipboard"
        ) ?? makeFallbackImage()
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }

    static func makeFallbackImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let board = NSBezierPath(
                roundedRect: NSRect(x: 3.5, y: 1.5, width: 11, height: 13),
                xRadius: 1.5,
                yRadius: 1.5
            )
            board.lineWidth = 1.5
            board.stroke()

            NSColor.black.setFill()
            NSBezierPath(
                roundedRect: NSRect(x: 6, y: 12, width: 6, height: 4.5),
                xRadius: 1,
                yRadius: 1
            ).fill()

            let lines = NSBezierPath()
            lines.lineWidth = 1.5
            for y: CGFloat in [6, 9] {
                lines.move(to: NSPoint(x: 6, y: y))
                lines.line(to: NSPoint(x: 12, y: y))
            }
            lines.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
