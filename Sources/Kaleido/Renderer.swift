import AppKit
import CoreGraphics
import ImageIO
import KaleidoCore
import Metal
import MetalKit
import UniformTypeIdentifiers
import os

/// Must match `Uniforms` in the shader: 16 floats, then 7 int32s.
struct GPUUniforms {
    var width: Float = 0, height: Float = 0
    var rotation: Float = 0, sourceRotation: Float = 0
    var panX: Float = 0, panY: Float = 0
    var zoom: Float = 1, twist: Float = 0
    var hue: Float = 0, saturation: Float = 1, vignette: Float = 0
    var blurLod: Float = 0, time: Float = 0
    var aspectA: Float = 1, aspectB: Float = 1
    var mixAmount: Float = 0
    var segments: Int32 = 8, mode: Int32 = 0, transition: Int32 = 0, hasB: Int32 = 0
    var segmentsB: Int32 = 8, modeB: Int32 = 0, original: Int32 = 0
}

struct PhotoTexture {
    let texture: MTLTexture
    let aspect: Float
}

struct PhotoRef: Equatable {
    enum Source: Equatable { case file(URL), asset(String) }
    let id: UUID
    let source: Source
    var label: String {
        switch source { case .file(let u): return u.lastPathComponent; case .asset(let a): return a }
    }
}

enum PhotoLoader {
    static func texture(for ref: PhotoRef, queue: MTLCommandQueue) async throws -> PhotoTexture {
        switch ref.source {
        case .file(let url):
            return try TextureFactory.load(url: url, queue: queue)
        case .asset(let id):
            let image = try await PhotosService.image(assetID: id, maxDimension: CGFloat(TextureFactory.maxDimension))
            return try TextureFactory.make(from: image, queue: queue)
        }
    }
}

/// Everything the renderer needs from the app, so it stays testable and free of UI state.
@MainActor
protocol PhotoProvider: AnyObject {
    /// The next photo to show after `current`, or nil if nothing is enabled.
    func nextPhoto(after current: UUID?) -> PhotoRef?
}

enum TextureFactory {
    static let maxDimension = 2560

    /// Decodes and downsamples a photo (honouring EXIF orientation) into an sRGB mipmapped GPU texture.
    static func load(url: URL, queue: MTLCommandQueue) throws -> PhotoTexture {
        try BookmarkStore.withAccess(to: url) {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw LoadError.unreadable }
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDimension,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { throw LoadError.unreadable }
            return try make(from: image, queue: queue)
        }
    }

    static func make(from image: CGImage, queue: MTLCommandQueue) throws -> PhotoTexture {
        let w = image.width, h = image.height
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
              let data = ctx.data
        else { throw LoadError.unreadable }
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: true)
        desc.usage = .shaderRead
        guard let tex = queue.device.makeTexture(descriptor: desc) else { throw LoadError.gpu }
        tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: data, bytesPerRow: w * 4)
        guard let cb = queue.makeCommandBuffer(), let blit = cb.makeBlitCommandEncoder() else { throw LoadError.gpu }
        blit.generateMipmaps(for: tex)
        blit.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        return PhotoTexture(texture: tex, aspect: Float(w) / Float(h))
    }

    /// Shown when no photo is enabled yet: soft colour blobs, so Play always shows something alive.
    static func placeholder(queue: MTLCommandQueue) -> PhotoTexture {
        let w = 1024, h = 640
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.04, green: 0.07, blue: 0.14, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let blobs: [(CGFloat, CGFloat, CGFloat, [CGFloat])] = [
            (250, 380, 330, [0.95, 0.45, 0.25]), (700, 200, 380, [0.2, 0.7, 0.85]),
            (860, 520, 260, [0.7, 0.35, 0.9]), (480, 120, 240, [0.95, 0.85, 0.4]), (120, 120, 260, [0.3, 0.85, 0.5]),
        ]
        for (x, y, r, c) in blobs {
            let g = CGGradient(colorSpace: space, colorComponents: c + [0.9, c[0], c[1], c[2], 0], locations: [0, 1], count: 2)!
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
        }
        return (try? make(from: ctx.makeImage()!, queue: queue)) ?? PhotoTexture(texture: queue.device.makeTexture(descriptor: MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false))!, aspect: 1)
    }

    enum LoadError: Error { case unreadable, gpu }
}

/// Owns the GPU pipeline and the animation timeline (rotation, drift, photo changes, transitions).
/// Every display's view just asks it to draw; state advances once per frame no matter how many views.
@MainActor
final class KaleidoRenderer {
    let device: MTLDevice
    let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let log = Logger(subsystem: "local.kaleido.app", category: "render")

    weak var provider: PhotoProvider?
    var targetLook = Look()
    var secondsPerPhoto: Double = 20
    var transitionSeconds: Double = 2.5
    var transitionStyle: TransitionStyle = .random

    private(set) var look = Look()
    private var current: PhotoTexture
    private var currentID: UUID?
    private var currentRef: PhotoRef?
    private var incomingRef: PhotoRef?
    private var history: [PhotoRef] = []
    private var goingBack = false
    private var incoming: PhotoTexture?
    private var incomingID: UUID?
    private var pending: (PhotoTexture, PhotoRef)?
    private var loading = false
    private var failures = 0
    private var retryAt = 0.0

    private var lastTick: CFTimeInterval?
    private var shownFor: Double = 0
    private var transitionClock: Double?
    private var activeStyle: TransitionStyle = .dissolve
    private var rotation = 0.0, sourceRotation = 0.0, driftPhase = 0.0, huePhase = 0.0, breathPhase = 0.0, clock = 0.0
    private var skipRequested = false
    /// Called just before a new photo starts fading in, so the app can switch looks in step with it.
    var willStartTransition: (() -> Void)?
    // Mirror mode and count belong to each photo: during a cross-fade the outgoing photo keeps its shape and
    // the incoming one already has the new look, so a look change never snaps mid-fade.
    private var currentShape = (mode: MirrorMode.radial, segments: 12)
    private var incomingShape = (mode: MirrorMode.radial, segments: 12)
    // Dragging the preview: an extra pan in photo space that keeps gliding after release, like a globe.
    private var userPan = SIMD2<Double>(0, 0)
    private var panVelocity = SIMD2<Double>(0, 0)
    private var dragging = false
    private var lastDragTime: CFTimeInterval = 0

    // Frame-pacing stats, printed when KALEIDO_DEBUG is set.
    private var statFrames = 0, statCPU = 0.0, statWorst = 0.0, statSince = CACurrentMediaTime()
    let debug = ProcessInfo.processInfo.environment["KALEIDO_DEBUG"] != nil

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        do {
            let lib = try device.makeLibrary(source: Shaders.source, options: nil)
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = lib.makeFunction(name: "kaleido_vertex")
            d.fragmentFunction = lib.makeFunction(name: "kaleido_fragment")
            d.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipeline = try device.makeRenderPipelineState(descriptor: d)
        } catch {
            NSLog("Kaleido: shader compile failed: \(error)")
            return nil
        }
        current = TextureFactory.placeholder(queue: queue)
    }

    // MARK: Timeline

    /// Advances the animation to `now`. Safe to call from every view's draw; only the first call per
    /// frame moves time (calls closer together than a quarter of a frame are ignored).
    func tick(now: CFTimeInterval, minStep: Double = 1.0 / 120) {
        guard let last = lastTick else { lastTick = now; return }
        let raw = now - last
        if raw < minStep { return }
        lastTick = now
        let dt = min(raw, 0.1)   // a long pause (sleep, covered window) must not make things jump
        advance(dt)
    }

    /// Call when rendering resumes after a pause so the first frame does not carry a stale delta.
    func resetClock() { lastTick = nil }

    func advance(_ dt: Double) {
        clock += dt
        look = look.eased(toward: targetLook, by: 1 - exp(-dt * 0.6))
        let m = look.motion   // master multiplier: 0 is perfectly still
        rotation += look.rotationSpeed * m * .pi / 180 * dt
        sourceRotation += (look.rotationSpeed * .pi / 180 * -0.4 + look.driftSpeed * 0.008) * m * dt
        driftPhase += look.driftSpeed * m * dt * 0.25
        huePhase += look.hueSpeed * m * .pi / 180 * dt
        breathPhase += m * dt * (2 * .pi / 600)   // one breath per ten minutes at full motion
        if !dragging {
            userPan += panVelocity * dt
            panVelocity *= exp(-dt * 0.9)   // friction: a flick coasts for a few seconds
            if simd_length(panVelocity) < 1e-4 { panVelocity = .zero }
        }
        // Mirrored-repeat sampling makes any pan valid; keep the number small so float precision holds.
        userPan.x = userPan.x.truncatingRemainder(dividingBy: 40)
        userPan.y = userPan.y.truncatingRemainder(dividingBy: 40)
        if transitionClock == nil { currentShape = (look.mode, look.segments) }

        if var t = transitionClock {
            t += dt
            if t >= transitionSeconds {
                if let incoming {
                    if let cur = currentRef, !goingBack { history.append(cur); if history.count > 40 { history.removeFirst() } }
                    goingBack = false
                    current = incoming; currentID = incomingID; currentRef = incomingRef
                    currentShape = incomingShape
                }
                incoming = nil; incomingID = nil; incomingRef = nil
                transitionClock = nil
                shownFor = 0
            } else {
                transitionClock = t
            }
        } else {
            shownFor += dt
            let due = shownFor >= secondsPerPhoto || skipRequested || currentID == nil
            if let (tex, ref) = pending, due {
                let id: UUID? = ref.id
                pending = nil
                skipRequested = false
                if id == currentID && id != nil {
                    shownFor = 0
                } else {
                    willStartTransition?()   // may change targetLook (look shuffle)
                    if targetLook.mode != look.mode || targetLook.segments != look.segments { look = look.eased(toward: targetLook, by: 0) }
                    incomingShape = (targetLook.mode, targetLook.segments)
                    incoming = tex; incomingID = id; incomingRef = ref
                    activeStyle = transitionStyle == .random ? TransitionStyle.concrete.randomElement()! : transitionStyle
                    transitionClock = 0
                }
            }
        }
        if pending == nil, !loading, transitionClock == nil { startLoad() }
    }

    func skip() { skipRequested = true }

    /// Goes back to the photo shown before the current one, if any.
    func previous() {
        guard let last = history.popLast() else { return }
        goingBack = true
        pending = nil
        loadAsync(last, force: true)
    }

    var canGoBack: Bool { !history.isEmpty }

    // MARK: Dragging

    func beginDrag() {
        dragging = true
        panVelocity = .zero
        lastDragTime = CACurrentMediaTime()
    }

    /// `delta` is the pointer movement in screen heights (y up).
    func drag(by delta: SIMD2<Double>) {
        let now = CACurrentMediaTime()
        let dt = max(now - lastDragTime, 1.0 / 240)
        lastDragTime = now
        let move = -delta / max(look.zoom, 0.1)
        userPan += move
        panVelocity = panVelocity * 0.6 + (move / dt) * 0.4
    }

    func endDrag() {
        dragging = false
        // A pause before letting go means "put it down here", not a flick.
        if CACurrentMediaTime() - lastDragTime > 0.08 { panVelocity = .zero }
        let speed = simd_length(panVelocity)
        if speed > 3 { panVelocity *= 3 / speed }
    }

    /// Jump straight to the target look (no easing); used for offscreen snapshots.
    func snapLook() {
        look = targetLook
        currentShape = (look.mode, look.segments)
        incomingShape = currentShape
    }

    /// Show a specific photo next (used by "Show now").
    func show(_ photo: PhotoRef) {
        loadAsync(photo, force: true)
    }

    private func startLoad() {
        guard let provider, clock >= retryAt else { return }
        guard let ref = provider.nextPhoto(after: currentID) else { return }
        if ref.id == currentID { shownFor = 0; return }
        loadAsync(ref, force: false)
    }

    private func loadAsync(_ ref: PhotoRef, force: Bool) {
        loading = true
        let queue = self.queue
        Task.detached(priority: .utility) { [weak self] in
            let result: Result<PhotoTexture, Error>
            do { result = .success(try await PhotoLoader.texture(for: ref, queue: queue)) } catch { result = .failure(error) }
            await self?.finishLoad(result, ref: ref, force: force)
        }
    }

    private func finishLoad(_ result: Result<PhotoTexture, Error>, ref: PhotoRef, force: Bool) {
        loading = false
        switch result {
        case .success(let tex):
            failures = 0
            pending = (tex, ref)
            if debug { FileHandle.standardError.write(Data("kaleido: loaded \(tex.texture.width)x\(tex.texture.height)\n".utf8)) }
            if force { skipRequested = true }
        case .failure(let error):
            failures += 1
            if debug { FileHandle.standardError.write(Data("kaleido: load failed \(ref.label.prefix(12)): \(error)\n".utf8)) }
            log.error("could not load \(ref.label): \(String(describing: error))")
            // The next tick asks the provider for another photo; give up quietly after repeated failures.
            pending = nil
            retryAt = clock + min(pow(2, Double(failures)), 60)   // back off so a broken photo cannot spin the loader
        }
    }

    // MARK: Drawing

    func makeUniforms(width: Double, height: Double, original: Bool = false) -> GPUUniforms {
        var u = GPUUniforms()
        u.width = Float(width); u.height = Float(height)
        u.original = original ? 1 : 0
        u.rotation = Float(rotation.truncatingRemainder(dividingBy: 2 * .pi))
        u.sourceRotation = Float(sourceRotation.truncatingRemainder(dividingBy: 2 * .pi))
        let amp = look.drift * 0.45
        u.panX = Float(amp * (sin(driftPhase * 0.173) + 0.5 * sin(driftPhase * 0.311 + 1.3)) + userPan.x)
        u.panY = Float(amp * (cos(driftPhase * 0.137) + 0.5 * cos(driftPhase * 0.263 + 0.4)) + userPan.y)
        u.zoom = Float(look.zoom * exp(0.12 * look.breathing * sin(breathPhase)))
        u.twist = Float(look.twist)
        u.hue = Float((look.hueShift * .pi / 180 + huePhase).truncatingRemainder(dividingBy: 2 * .pi))
        u.saturation = Float(look.saturation)
        u.vignette = Float(look.vignette)
        u.blurLod = Float(look.blur * 5)
        u.time = Float(clock.truncatingRemainder(dividingBy: 1000))
        u.aspectA = current.aspect
        u.segments = Int32(currentShape.segments)
        u.mode = currentShape.mode.shaderIndex
        u.segmentsB = u.segments
        u.modeB = u.mode
        if let incoming, let t = transitionClock {
            u.hasB = 1
            u.aspectB = incoming.aspect
            u.mixAmount = Float(min(max(t / transitionSeconds, 0), 1))
            u.transition = activeStyle.shaderIndex
            u.segmentsB = Int32(incomingShape.segments)
            u.modeB = incomingShape.mode.shaderIndex
        }
        return u
    }

    func encode(into pass: MTLRenderPassDescriptor, drawable: MTLDrawable?, width: Double, height: Double, original: Bool = false,
                completion: ((MTLCommandBuffer) -> Void)? = nil) {
        guard let cb = queue.makeCommandBuffer(), let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        var u = makeUniforms(width: width, height: height, original: original)
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBytes(&u, length: MemoryLayout<GPUUniforms>.stride, index: 0)
        enc.setFragmentTexture(current.texture, index: 0)
        enc.setFragmentTexture((incoming ?? current).texture, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        if let drawable { cb.present(drawable) }
        if let completion { cb.addCompletedHandler(completion) }
        cb.commit()
    }

    func noteFrame() { recordFrame(cpu: 0) }

    private func recordFrame(cpu: Double) {
        statFrames += 1; statCPU += cpu; statWorst = max(statWorst, cpu)
        let now = CACurrentMediaTime()
        if now - statSince >= 5 {
            let fps = Double(statFrames) / (now - statSince)
            let line = String(format: "kaleido: %.1f fps total (all views), cpu/frame avg %.2f ms worst %.2f ms", fps, statCPU / Double(statFrames) * 1000, statWorst * 1000)
            FileHandle.standardError.write(Data((line + "\n").utf8))
            statFrames = 0; statCPU = 0; statWorst = 0; statSince = now
        }
    }

    // MARK: Offscreen (screenshots without screen-recording permission)

    func setPhotosImmediately(_ a: URL, _ b: URL? = nil, progress: Double = 0.5, style: TransitionStyle = .dissolve) throws {
        current = try TextureFactory.load(url: a, queue: queue)
        if let b {
            incoming = try TextureFactory.load(url: b, queue: queue)
            activeStyle = style
            transitionSeconds = 1
            transitionClock = progress
        }
    }

    func snapshot(width: Int, height: Int) -> CGImage? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        guard let target = device.makeTexture(descriptor: desc) else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let sem = DispatchSemaphore(value: 0)
        encode(into: pass, drawable: nil, width: Double(width), height: Double(height)) { _ in sem.signal() }
        sem.wait()
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        target.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

/// Draws the shared renderer into IOSurfaces and shows them through a plain CALayer.
/// (A CAMetalLayer window never showed any content on the built-in notched display, even though every
/// frame was presented; ordinary layers do show there, so Metal renders offscreen and the surface is
/// handed to Core Animation instead.) Stops drawing while its window is covered or minimised.
final class KaleidoView: NSView {
    private let renderer: KaleidoRenderer
    private var link: CADisplayLink?
    private var surfaces: [(surface: IOSurface, texture: MTLTexture)] = []
    private var nextSurface = 0
    private var inFlight = 0
    private var observer: NSObjectProtocol?
    private(set) var occluded = false
    private(set) var drawCount = 0
    private(set) var presentCount = 0
    nonisolated(unsafe) var lastProbe: (UInt8, UInt8, UInt8) = (0, 0, 0)
    private(set) var pixelWidth = 0, pixelHeight = 0
    private let maxInFlight = 2
    var preferredFramesPerSecond: Int { didSet { applyRate() } }
    var suspended = false { didSet { refreshPause() } }
    var isPaused: Bool { link?.isPaused ?? true }
    /// Preview only: show the photo itself instead of the kaleidoscope.
    var showOriginal = false
    /// Preview only: dragging moves the photo inside the mirrors (and keeps gliding after release).
    var acceptsDrag = false

    override func mouseDown(with event: NSEvent) {
        guard acceptsDrag else { return super.mouseDown(with: event) }
        MainActor.assumeIsolated { renderer.beginDrag() }
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard acceptsDrag, bounds.height > 0 else { return super.mouseDragged(with: event) }
        // Points to screen heights; AppKit's y already points up, like the shader's.
        let d = SIMD2<Double>(event.deltaX, -event.deltaY) / Double(bounds.height)
        MainActor.assumeIsolated { renderer.drag(by: d) }
    }

    override func mouseUp(with event: NSEvent) {
        guard acceptsDrag else { return super.mouseUp(with: event) }
        MainActor.assumeIsolated { renderer.endDrag() }
        NSCursor.pop()
    }

    override func resetCursorRects() {
        if acceptsDrag { addCursorRect(bounds, cursor: .openHand) }
    }

    @MainActor
    init(renderer: KaleidoRenderer, fps: Int) {
        self.renderer = renderer
        self.preferredFramesPerSecond = fps
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contentsGravity = .resize
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.isOpaque = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        link?.invalidate(); link = nil
        if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
        guard let window else { return }
        let l = displayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
        applyRate()
        occluded = !window.occlusionState.contains(.visible) && window.isVisible
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self, weak window] _ in
            guard let self, let window else { return }
            self.occluded = !window.occlusionState.contains(.visible)
            MainActor.assumeIsolated { self.renderer.resetClock() }
            self.refreshPause()
        }
        refreshPause()
    }

    private func applyRate() {
        let f = Float(preferredFramesPerSecond)
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: f, maximum: f, preferred: f)
    }

    private func refreshPause() { link?.isPaused = suspended || occluded }

    private func ensureSurfaces() -> Bool {
        let scale = window?.backingScaleFactor ?? 2
        let w = max(Int(bounds.width * scale), 2), h = max(Int(bounds.height * scale), 2)
        if w == pixelWidth && h == pixelHeight && !surfaces.isEmpty { return true }
        surfaces = []
        for _ in 0..<3 {
            guard let surface = IOSurface(properties: [
                .width: w, .height: h, .bytesPerElement: 4, .pixelFormat: 0x4247_5241 /* 'BGRA' */,
            ]) else { return false }
            surface.setAttachment(CGColorSpace(name: CGColorSpace.sRGB)!.copyPropertyList() as Any, forKey: "IOSurfaceColorSpace")
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            guard let tex = renderer.device.makeTexture(descriptor: d, iosurface: surface, plane: 0) else { return false }
            surfaces.append((surface, tex))
        }
        pixelWidth = w; pixelHeight = h
        return true
    }

    @objc private func tick(_ link: CADisplayLink) {
        drawCount += 1
        guard inFlight < maxInFlight, ensureSurfaces() else { return }
        MainActor.assumeIsolated { renderer.tick(now: CACurrentMediaTime()) }
        let entry = surfaces[nextSurface]
        nextSurface = (nextSurface + 1) % surfaces.count
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = entry.texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        inFlight += 1
        let debug = renderer.debug
        MainActor.assumeIsolated {
            renderer.encode(into: pass, drawable: nil, width: Double(pixelWidth), height: Double(pixelHeight), original: showOriginal) { [weak self] cb in
                if debug, cb.status == .error { FileHandle.standardError.write(Data("kaleido: GPU error \(String(describing: cb.error))\n".utf8)) }
                if debug {
                    var px = [UInt8](repeating: 0, count: 4)
                    entry.texture.getBytes(&px, bytesPerRow: 4, from: MTLRegionMake2D(entry.texture.width / 2, entry.texture.height / 2, 1, 1), mipmapLevel: 0)
                    self?.lastProbe = (px[2], px[1], px[0])
                }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.inFlight -= 1
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    self.layer?.contents = entry.surface
                    CATransaction.commit()
                    self.presentCount += 1
                }
            }
        }
        if debug { MainActor.assumeIsolated { renderer.noteFrame() } }
    }

    deinit {
        link?.invalidate()
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
