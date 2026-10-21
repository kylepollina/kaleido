import AVFoundation
import CoreVideo
import Metal
import QuartzCore

/// A looping, muted video that keeps a mipmapped GPU texture up to date, so the shader can sample it exactly like
/// a photo. Frames are decoded in hardware at no more than `maxWidth` pixels wide.
final class VideoSource: @unchecked Sendable {
    let texture: MTLTexture
    let aspect: Float
    private let player: AVPlayer
    private let output: AVPlayerItemVideoOutput
    private let cache: CVMetalTextureCache
    private var endObserver: NSObjectProtocol?
    private(set) var isPaused = false
    private let playRate: Float

    static let maxWidth = 1920

    /// Loads the video and waits for its first frame (so a fade never starts on black).
    static func load(url: URL, queue: MTLCommandQueue) async throws -> VideoSource {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw TextureFactory.LoadError.unreadable }
        let (natural, transform) = try await track.load(.naturalSize, .preferredTransform)
        let size = natural.applying(transform)
        let w0 = abs(size.width), h0 = abs(size.height)
        guard w0 > 0, h0 > 0 else { throw TextureFactory.LoadError.unreadable }
        let scale = min(1, Double(maxWidth) / Double(w0))
        let w = Int((Double(w0) * scale / 2).rounded()) * 2, h = Int((Double(h0) * scale / 2).rounded()) * 2
        // Real time, as macOS plays them (Apple's aerials are 240 fps clips of about five minutes; slowing them to
        // 30 decoded frames a second made each loop last 40 minutes and looked sluggish).
        let rate: Float = 1
        let source = try VideoSource(asset: asset, width: w, height: h, rate: rate, queue: queue)
        try await source.waitForFirstFrame(queue: queue)
        return source
    }

    private init(asset: AVAsset, width: Int, height: Int, rate: Float, queue: MTLCommandQueue) throws {
        playRate = rate
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(nil, nil, queue.device, nil, &cache) == kCVReturnSuccess, let cache else {
            throw TextureFactory.LoadError.gpu
        }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: true)
        desc.usage = .shaderRead
        desc.storageMode = .private
        guard let tex = queue.device.makeTexture(descriptor: desc) else { throw TextureFactory.LoadError.gpu }
        self.cache = cache
        texture = tex
        aspect = Float(width) / Float(height)
        output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        let item = AVPlayerItem(asset: asset)
        item.add(output)
        player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .none
        player.preventsDisplaySleepDuringVideoPlayback = false
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: nil) { [weak player] _ in
            player?.seek(to: .zero)   // loop (the rate is kept)
        }
        player.rate = playRate
    }

    deinit {
        player.pause()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        if paused { player.pause() } else { player.rate = playRate }
    }

    private func waitForFirstFrame(queue: MTLCommandQueue) async throws {
        for _ in 0..<150 {   // up to about 5 seconds
            if let cb = queue.makeCommandBuffer(), update(into: cb) {
                cb.commit()
                await cb.completed()
                return
            }
            try await Task.sleep(for: .milliseconds(33))
        }
        throw TextureFactory.LoadError.unreadable
    }

    /// Copies the newest decoded frame (if there is a new one) into the texture and rebuilds its mipmaps.
    /// Returns whether a frame was copied.
    @discardableResult
    func update(into cb: MTLCommandBuffer) -> Bool {
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: time),
              let pixels = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return false }
        let w = CVPixelBufferGetWidth(pixels), h = CVPixelBufferGetHeight(pixels)
        var cvTex: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(nil, cache, pixels, nil, .bgra8Unorm, w, h, 0, &cvTex) == kCVReturnSuccess,
              let cvTex, let frame = CVMetalTextureGetTexture(cvTex),
              let blit = cb.makeBlitCommandEncoder() else { return false }
        let cw = min(w, texture.width), ch = min(h, texture.height)
        blit.copy(from: frame, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
                  sourceSize: MTLSize(width: cw, height: ch, depth: 1),
                  to: texture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())
        blit.generateMipmaps(for: texture)
        blit.endEncoding()
        cb.addCompletedHandler { _ in withExtendedLifetime((cvTex, pixels)) {} }   // keep the frame alive until copied
        return true
    }
}
