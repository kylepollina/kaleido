import AppKit
import AVFoundation
import ImageIO
import KaleidoCore

enum Thumbnails {
    static func image(forAsset id: String) async -> NSImage? {
        let key = "asset:\(id)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let cg = await PhotosService.thumbnail(assetID: id) else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(img, forKey: key, cost: Self.bytes(img))
        return img
    }

    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 600
        c.totalCostLimit = 80 * 1_048_576   // bytes of decoded pixels; big albums can't pile up hundreds of MB
        return c
    }()

    /// A small, orientation-corrected thumbnail, decoded off the main thread and cached by path.
    static func image(for url: URL, maxPixels: Int = 360) async -> NSImage? {
        let key = "\(url.path)@\(maxPixels)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        if VideoFiles.isVideo(url) {
            // Aerials come with Apple's own still; other videos give a frame from a second in.
            if let still = AerialScanner.thumbnail(for: url) { return await image(for: still, maxPixels: maxPixels) }
            let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: maxPixels, height: maxPixels)
            guard let cg = try? await gen.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image else { return nil }
            let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            cache.setObject(img, forKey: key, cost: Self.bytes(img))
            return img
        }
        let cg: CGImage? = await Task.detached(priority: .utility) {
            BookmarkStore.withAccess(to: url) {
                guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                return CGImageSourceCreateThumbnailAtIndex(src, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                ] as CFDictionary)
            }
        }.value
        guard let cg else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(img, forKey: key, cost: Self.bytes(img))
        return img
    }
}

extension Thumbnails {
    /// Decoded size of a thumbnail, for the cache's memory budget.
    static func bytes(_ image: NSImage) -> Int {
        image.representations.map { $0.pixelsWide * $0.pixelsHigh * 4 }.max() ?? Int(image.size.width * image.size.height * 4)
    }
}
