import Foundation
import ImageIO
import UIKit

/// Thread-safe decoded-image memory cache (NSCache is internally synchronized).
final class DecodedImageCache: @unchecked Sendable {
    private let storage = NSCache<NSString, UIImage>()
    init() {
        storage.totalCostLimit = 120 * 1024 * 1024
        storage.countLimit = 600
    }
    func image(_ key: String) -> UIImage? { storage.object(forKey: key as NSString) }
    func insert(_ image: UIImage, _ key: String) {
        let pixels = Int(image.size.width * image.scale * image.size.height * image.scale)
        storage.setObject(image, forKey: key as NSString, cost: pixels * 4)
    }
}

/// Artwork loading for every native surface. Replaces AsyncImage, which kept no
/// useful cache, re-fetched on every scroll and decoded full-size images on the
/// main thread at first render.
/// - Downloads go through a 300 MB disk URLCache (TMDB art is immutable).
/// - Decoding and downsampling to the drawn size happen off the main thread.
/// - Concurrent requests for the same image share one download.
actor ImagePipeline {
    static let shared = ImagePipeline()
    nonisolated static let memory = DecodedImageCache()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024,
                                          directory: URL.cachesDirectory.appending(path: "Artwork", directoryHint: .isDirectory))
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
    }

    nonisolated static func key(_ url: URL, _ maxPixel: Int) -> String { "\(url.absoluteString)#\(maxPixel)" }

    /// Synchronous memory hit so recycled cells draw immediately, without a placeholder flash.
    nonisolated static func cached(_ url: URL?, maxPixel: Int) -> UIImage? {
        guard let url else { return nil }
        return memory.image(key(url, maxPixel))
    }

    func image(_ url: URL, maxPixel: Int) async -> UIImage? {
        let key = Self.key(url, maxPixel)
        if let hit = Self.memory.image(key) { return hit }
        if let running = inFlight[key] { return await running.value }
        let session = self.session
        let task = Task.detached(priority: .userInitiated) { () async -> UIImage? in
            guard let result = try? await session.data(from: url) else { return nil }
            let (data, response) = result
            if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) { return nil }
            return ImagePipeline.downsample(data, maxPixel: maxPixel)
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image { Self.memory.insert(image, key) }
        return image
    }

    /// Decodes at most `maxPixel` on the longest side, fully decoded off the main thread.
    nonisolated static func downsample(_ data: Data, maxPixel: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(64, maxPixel),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
