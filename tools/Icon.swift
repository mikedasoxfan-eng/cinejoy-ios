import AppKit

let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                             isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedRed: 0.025, green: 0.04, blue: 0.03, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
let green = NSColor(calibratedRed: 0.584, green: 1, blue: 0.314, alpha: 1)
green.setStroke()
let frame = NSBezierPath(roundedRect: NSRect(x: 210, y: 240, width: 604, height: 544), xRadius: 100, yRadius: 100)
frame.lineWidth = 38
frame.stroke()
green.setFill()
for x in stride(from: 300, through: 720, by: 140) {
    NSBezierPath(roundedRect: NSRect(x: x, y: 706, width: 62, height: 28), xRadius: 8, yRadius: 8).fill()
}
let play = NSBezierPath()
play.move(to: NSPoint(x: 430, y: 360))
play.line(to: NSPoint(x: 650, y: 500))
play.line(to: NSPoint(x: 430, y: 640))
play.close()
play.fill()
NSGraphicsContext.restoreGraphicsState()
let destination = CommandLine.arguments[1]
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
