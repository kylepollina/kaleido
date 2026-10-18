import AppKit
import ImageIO
import KaleidoCore

enum Thumbnails {
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 600
        return c
    }()

    /// A small, orientation-corrected thumbnail, decoded off the main thread and cached by path.
    static func image(for url: URL, maxPixels: Int = 360) async -> NSImage? {
        let key = "\(url.path)@\(maxPixels)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
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
        cache.setObject(img, forKey: key)
        return img
    }
}
