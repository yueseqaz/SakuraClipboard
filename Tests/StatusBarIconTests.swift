import Cocoa

@main
struct StatusBarIconTests {
    static func main() {
        _ = NSApplication.shared
        verify(StatusBarIcon.makeImage(), name: "Menu bar symbol")
        verify(StatusBarIcon.makeFallbackImage(), name: "Fallback artwork")
        print("Status bar icon tests passed")
    }

    private static func verify(_ image: NSImage, name: String) {
        precondition(image.isTemplate, "\(name) must adapt to light and dark menu bars")
        precondition(image.size == NSSize(width: 18, height: 18), "\(name) has the wrong size")

        for scale in [1, 2] {
            let pixels = 18 * scale
            guard let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixels,
                pixelsHigh: pixels,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
                fatalError("Cannot create bitmap context")
            }
            bitmap.size = image.size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            image.draw(in: NSRect(origin: .zero, size: image.size))
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()

            var visiblePixels = 0
            var transparentPixels = 0
            for y in 0..<pixels {
                for x in 0..<pixels {
                    let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
                    if alpha > 0.1 { visiblePixels += 1 }
                    if alpha < 0.1 { transparentPixels += 1 }
                }
            }
            precondition(visiblePixels > 20 * scale * scale, "\(name) is blank at \(scale)x")
            precondition(transparentPixels > 20 * scale * scale, "\(name) needs a transparent background")
        }
    }
}
