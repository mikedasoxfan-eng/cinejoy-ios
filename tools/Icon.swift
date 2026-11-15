import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Cinejoy's official high-resolution export of https://cinejoy.pk/favicon.svg
let input = URL(fileURLWithPath: "Resources/Brand/pwa-512.png")
guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let context = CGContext(data: nil, width: 1024, height: 1024,
                              bitsPerComponent: 8, bytesPerRow: 4096,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("Cannot render Cinejoy's official favicon")
}
// A supported 32-bit opaque Core Graphics context; iOS supplies the corner mask.
context.setFillColor(CGColor(gray: 5.0 / 255.0, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
context.interpolationQuality = .high
context.draw(artwork, in: CGRect(x: 80, y: 80, width: 864, height: 864))
guard let image = context.makeImage() else { fatalError("No icon image") }
for path in [CommandLine.arguments[1], "dist/AppIcon.png"] {
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Cannot write favicon icon")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Cannot finish favicon icon") }
}
print("Rendered Cinejoy's official favicon at 1024px")
