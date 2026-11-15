import AppKit

// Original Cinejoy artwork: https://cinejoy.pk/favicon.svg
// Official PNG fallback: https://cinejoy.pk/pwa-512.png
let source = NSImage(contentsOfFile: "Resources/Brand/favicon.svg")
    ?? NSImage(contentsOfFile: "Resources/Brand/pwa-512.png")
guard let source, source.size.width > 0, source.size.height > 0 else {
    fatalError("Cinejoy favicon could not be loaded")
}
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                             bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
                             isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.current?.imageInterpolation = .high
// Match Cinejoy's manifest background; iOS applies its own corner mask.
NSColor(calibratedWhite: 5.0 / 255.0, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
let available = 864.0
let scale = min(available / source.size.width, available / source.size.height)
let width = source.size.width * scale
let height = source.size.height * scale
source.draw(in: NSRect(x: (1024 - width) / 2, y: (1024 - height) / 2, width: width, height: height),
            from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
let data = bitmap.representation(using: .png, properties: [:])!
for path in [CommandLine.arguments[1], "dist/AppIcon.png"] {
    let destination = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: destination)
}
print("Rendered original Cinejoy favicon as a 1024px opaque iOS icon")
