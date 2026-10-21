import AppKit
import CoreGraphics
import ImageIO
import KaleidoCore
import Metal
import MetalKit
import UniformTypeIdentifiers
import os

/// Must match `Uniforms` in the shader: 17 floats, then 9 int32s.
struct GPUUniforms {
    var width: Float = 0, height: Float = 0
    var rotation: Float = 0, sourceRotation: Float = 0
    var panX: Float = 0, panY: Float = 0
    var zoom: Float = 1, twist: Float = 0
    var hue: Float = 0, saturation: Float = 1, vignette: Float = 0
    var time: Float = 0
    var aspectA: Float = 1, aspectB: Float = 1
    var mixAmount: Float = 0, morph: Float = 0, outline: Float = 0
    var segments: Int32 = 8, mode: Int32 = 0, transition: Int32 = 0, hasB: Int32 = 0
    var segmentsB: Int32 = 8, modeB: Int32 = 0, original: Int32 = 0, segmentsMorph: Int32 = 8
    var outlines: Int32 = 0
}

struct PhotoTexture {
    let texture: MTLTexture
    let aspect: Float
    /// Set for a video: it refreshes `texture` with each new frame.
    var video: VideoSource? = nil
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
        case .file(let url) where VideoFiles.isVideo(url):
            let video = try await VideoSource.load(url: url, queue: queue)
            return PhotoTexture(texture: video.texture, aspect: video.aspect, video: video)
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
    /// +1 push, -1 pull, 0 neither: the photo keeps sliding as if dragged from a corner toward the
    /// centre (or back out), so the pattern pours into the middle or spreads out of it.
    var zoomFlow = 0
    /// The current slide, easing toward the wanted one so starting and stopping are gentle.
    private var flowVelocity = SIMD2<Double>(0, 0)
    /// Photo heights per second at speed 1 (scaled by the speed control like every other motion).
    private let flowSpeed = 0.008

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
    private var rotation = 0.0, sourceRotation = 0.0, driftPhase = 0.0, huePhase = 0.0, breathPhase = 0.0, swirlPhase = 0.0, clock = 0.0
    private var skipRequested = false
    /// Length of the fade in progress, and of fades started by Next or Back.
    private var fadeSeconds = 2.5
    private let manualFadeSeconds = 3.0
    private var reversing = false
    private var refadeRequested = false
    /// Bumped by every load, so a slower, older load can never replace the photo asked for last.
    private var loadGeneration = 0
    /// Called just before a new photo starts fading in, so the app can switch looks in step with it.
    /// Gets the incoming photo's id and whether it came from Back.
    var willStartTransition: ((UUID?, Bool) -> Void)?
    /// Back during a fade: the fade runs in reverse, so the app can put the old pattern back too.
    var didReverseTransition: (() -> Void)?
    // Mirror mode and count belong to each photo: during a cross-fade the outgoing photo keeps its shape and
    // the incoming one already has the new look, so a look change never snaps mid-fade.
    private var dynamicCount: Int?, morphTo: Int?, mirrorKey: String?
    private var morphClock = 0.0, mirrorTimer = 0.0
    private var currentShape = (mode: MirrorMode.radial, segments: 12)
    private var incomingShape = (mode: MirrorMode.radial, segments: 12)
    // Dragging the preview: an extra pan in photo space that keeps gliding after release, like a globe.
    private var userPan = SIMD2<Double>(0, 0)
    private var panVelocity = SIMD2<Double>(0, 0)
    private var dragging = false
    private var lastDragTime: CFTimeInterval = 0
    /// Where a scene wants the photo to sit; the pan glides there and then stays.
    private var panGoal: SIMD2<Double>?
    /// Called when the user lets go of the preview after dragging the photo.
    var didDrag: (() -> Void)?
    /// A scene is showing: keep this photo until asked to move on.
    var holdPhoto = false

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
        swirlPhase += m * dt * (2 * .pi / 480)    // a swaying swirl swings through once every eight minutes at speed 1
        // Push slides the photo along the mirror wedge's own axis: whatever the photo shows at the wedge's
        // outer edge then travels toward its point, so the pattern pours into the centre (of the screen for the
        // mandalas, of each cell for hex). The wedge turns with `sourceRotation`, so the slide follows it; a
        // fixed direction would flip between in and out as the pattern turns. Plain tilings have no centre and
        // simply flow diagonally.
        let axis: Double
        switch look.mode {
        case .radial, .fractal: axis = .pi / (2 * Double(max(currentShape.segments, 2)))
        case .hex: axis = .pi / 12
        default: axis = .pi / 4
        }
        let a = sourceRotation + axis
        let wanted = SIMD2<Double>(cos(a), sin(a)) * Double(zoomFlow) * flowSpeed * m
        flowVelocity += (wanted - flowVelocity) * (1 - exp(-dt * 0.5))
        if !dragging, panGoal == nil { userPan += flowVelocity * dt }
        if targetLook.hueSpeed == 0 {
            // Cycling is off: let the colour it built up ease back out, so the photo returns to its own colours.
            huePhase = remainder(huePhase, 2 * .pi) * exp(-dt * 1.2)
            if abs(huePhase) < 1e-4 { huePhase = 0 }
        }
        if let goal = panGoal, !dragging {
            // The mirrored photo repeats every 2 heights (and 2 widths), so head for the nearest copy of the
            // goal: a short, gentle move instead of sweeping across many tiles.
            let aspect = Double((incoming ?? current).aspect)
            let period = SIMD2<Double>(2 * max(aspect, 0.1), 2)
            let near = goal + ((userPan - goal) / period).rounded(.toNearestOrAwayFromZero) * period
            userPan += (near - userPan) * (1 - exp(-dt * 1.2))
            if simd_length(near - userPan) < 1e-4 { userPan = near; panGoal = nil }
        } else if !dragging {
            userPan += panVelocity * dt
            panVelocity *= exp(-dt * 0.9)   // friction: a flick coasts for a few seconds
            if simd_length(panVelocity) < 1e-4 { panVelocity = .zero }
        }
        // Mirrored-repeat sampling makes any pan valid; keep the number small so float precision holds.
        userPan.x = userPan.x.truncatingRemainder(dividingBy: 40)
        userPan.y = userPan.y.truncatingRemainder(dividingBy: 40)
        updateDynamicMirrors(dt)
        if transitionClock == nil { currentShape = (look.mode, dynamicCount ?? look.segments) }

        if var t = transitionClock, reversing {
            // Back during a fade: fade back out to the photo that was showing.
            t -= dt * 3
            if t <= 0 {
                incoming = nil; incomingID = nil; incomingRef = nil
                transitionClock = nil
                reversing = false
                shownFor = 0
            } else {
                transitionClock = t
            }
        } else if var t = transitionClock {
            t += dt
            if t >= fadeSeconds {
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
            let due = (shownFor >= secondsPerPhoto && !holdPhoto) || skipRequested || currentID == nil
            if let (tex, ref) = pending, due {
                let id: UUID? = ref.id
                pending = nil
                // Next and Back answer quickly; the slideshow's own changes take the full, slow fade.
                fadeSeconds = skipRequested && currentID != nil ? min(transitionSeconds, manualFadeSeconds) : transitionSeconds
                skipRequested = false
                let refade = refadeRequested
                refadeRequested = false
                if id == currentID && id != nil && !refade {
                    shownFor = 0
                } else {
                    willStartTransition?(id, goingBack)   // may change targetLook (the scene's pattern)
                    if targetLook.mode != look.mode || targetLook.segments != look.segments { look = look.eased(toward: targetLook, by: 0) }
                    incomingShape = (targetLook.mode, startingMirrorCount(for: targetLook))
                    incoming = tex; incomingID = id; incomingRef = ref
                    activeStyle = transitionStyle == .random ? TransitionStyle.concrete.randomElement()! : transitionStyle
                    transitionClock = 0
                }
            }
        }
        if pending == nil, !loading, transitionClock == nil { startLoad() }
    }

    // MARK: Dynamic mirrors

    /// Seconds between mirror-count changes and how long each cross-fade lasts, at speed 1.
    private let mirrorChangeInterval = 180.0, mirrorMorphSeconds = 40.0

    private func dynamicKey(_ l: Look) -> String { "\(l.mode.rawValue)-\(l.segments)-\(l.mirrorsMin)-\(l.mirrorsMax)" }

    /// The count a look starts at: its own while it is the one already wandering, else its base count kept in range.
    private func startingMirrorCount(for l: Look) -> Int {
        guard l.dynamicMirrors else { return l.segments }
        if dynamicKey(l) == mirrorKey, let n = dynamicCount { return n }
        return min(max(l.segments, l.mirrorsMin), l.mirrorsMax)
    }

    private func updateDynamicMirrors(_ dt: Double) {
        guard look.dynamicMirrors else { dynamicCount = nil; morphTo = nil; mirrorKey = nil; return }
        let key = dynamicKey(look)
        if key != mirrorKey {
            dynamicCount = startingMirrorCount(for: look)
            mirrorKey = key
            morphTo = nil; morphClock = 0; mirrorTimer = 0
        }
        // A fixed, slow pace (every few minutes) whatever the speed control says; stopped only when motion is
        // off, and frozen while a photo cross-fades so the two never fight.
        let pace: Double = look.motion > 0 ? 1 : 0
        guard pace > 0, transitionClock == nil, let n = dynamicCount else { return }
        if let to = morphTo {
            morphClock += dt * pace / mirrorMorphSeconds
            if morphClock >= 1 { dynamicCount = to; morphTo = nil; morphClock = 0; mirrorTimer = 0 }
        } else {
            mirrorTimer += dt * pace
            if mirrorTimer >= mirrorChangeInterval {
                var g = SystemRandomNumberGenerator()
                morphTo = Look.nextMirrorCount(from: n, min: look.mirrorsMin, max: look.mirrorsMax, using: &g)
                morphClock = 0
            }
        }
    }

    func skip() { skipRequested = true }

    /// Goes back to the photo shown before the current one, if any.
    func previous() {
        if transitionClock != nil, incoming != nil, !reversing {
            // Mid-fade, "back" means the photo that is fading out.
            reversing = true
            pending = nil
            didReverseTransition?()
            return
        }
        guard let last = history.popLast() else { return }
        goingBack = true
        pending = nil
        loadAsync(last, force: true)
    }

    var canGoBack: Bool { !history.isEmpty }

    // MARK: Dragging

    /// Where the photo has been dragged to (a scene saves this).
    var pan: SIMD2<Double> { panGoal ?? userPan }

    /// Glides the photo to a scene's position and stops it there.
    func glidePan(to goal: SIMD2<Double>) {
        panVelocity = .zero
        panGoal = goal
    }

    func beginDrag() {
        dragging = true
        panGoal = nil
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
        didDrag?()
    }

    /// Jump straight to the target look (no easing); used for offscreen snapshots.
    /// The Settings > Effects switches change things right away instead of gliding there. Turning hue off also
    /// drops any hue the colour cycling had already built up, so the photo's real colours come straight back.
    func applyEffectSwitchesNow(hueAllowed: Bool) {
        look.hueShift = targetLook.hueShift
        look.hueSpeed = targetLook.hueSpeed
        look.saturation = targetLook.saturation
        look.vignette = targetLook.vignette
        look.twist = targetLook.twist
        look.outline = targetLook.outline
        look.dynamicMirrors = targetLook.dynamicMirrors
        if !hueAllowed { huePhase = 0 }
    }

    func snapLook() {
        look = targetLook
        currentShape = (look.mode, look.segments)
        incomingShape = currentShape
    }

    /// Offscreen snapshots only: freeze a mirror-count cross-fade part way.
    func forceMorph(to count: Int, progress: Double) {
        morphTo = count
        morphClock = progress
    }

    /// The photo on screen now (nil while the placeholder shows).
    var currentPhotoID: UUID? { currentID }
    /// The photo on screen and where it comes from (nil while the placeholder shows).
    var currentPhoto: PhotoRef? { currentRef }

    /// Show a specific photo next (used by "Show now").
    /// `refade`: fade even when it is the photo already showing (a scene putting a new pattern on it), so the
    /// pattern never jumps.
    func show(_ photo: PhotoRef, refade: Bool = false) {
        refadeRequested = refade
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
        loadGeneration += 1
        let generation = loadGeneration
        let queue = self.queue
        Task.detached(priority: .utility) { [weak self] in
            let result: Result<PhotoTexture, Error>
            do { result = .success(try await PhotoLoader.texture(for: ref, queue: queue)) } catch { result = .failure(error) }
            await self?.finishLoad(result, ref: ref, force: force, generation: generation)
        }
    }

    private func finishLoad(_ result: Result<PhotoTexture, Error>, ref: PhotoRef, force: Bool, generation: Int) {
        guard generation == loadGeneration else { return }   // superseded by a later request
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

    func makeUniforms(width: Double, height: Double, original: Bool = false, outlines: Bool = false) -> GPUUniforms {
        var u = GPUUniforms()
        u.width = Float(width); u.height = Float(height)
        u.original = original ? 1 : 0
        u.outlines = outlines ? 1 : 0
        u.rotation = Float(rotation.truncatingRemainder(dividingBy: 2 * .pi))
        u.sourceRotation = Float(sourceRotation.truncatingRemainder(dividingBy: 2 * .pi))
        let amp = look.drift * 0.45
        u.panX = Float(amp * (sin(driftPhase * 0.173) + 0.5 * sin(driftPhase * 0.311 + 1.3)) + userPan.x)
        u.panY = Float(amp * (cos(driftPhase * 0.137) + 0.5 * cos(driftPhase * 0.263 + 0.4)) + userPan.y)
        u.zoom = Float(look.zoom * exp(0.12 * look.breathing * sin(breathPhase)))
        u.twist = Float(look.swayingSwirl ? look.twist * sin(swirlPhase) : look.twist)
        u.hue = Float((look.hueShift * .pi / 180 + huePhase).truncatingRemainder(dividingBy: 2 * .pi))
        u.saturation = Float(look.saturation)
        u.vignette = Float(look.vignette)
        u.outline = Float(look.outline)
        u.time = Float(clock.truncatingRemainder(dividingBy: 1000))
        u.aspectA = current.aspect
        u.segments = Int32(currentShape.segments)
        u.mode = currentShape.mode.shaderIndex
        u.segmentsB = u.segments
        u.modeB = u.mode
        u.segmentsMorph = u.segments
        if let to = morphTo, transitionClock == nil {
            u.morph = Float(min(max(morphClock, 0), 1))
            u.segmentsMorph = Int32(to)
        }
        if let incoming, let t = transitionClock {
            u.hasB = 1
            u.aspectB = incoming.aspect
            u.mixAmount = Float(min(max(t / fadeSeconds, 0), 1))
            u.transition = activeStyle.shaderIndex
            u.segmentsB = Int32(incomingShape.segments)
            u.modeB = incomingShape.mode.shaderIndex
        }
        return u
    }

    func encode(into pass: MTLRenderPassDescriptor, drawable: MTLDrawable?, width: Double, height: Double, original: Bool = false, outlines: Bool = false,
                completion: (@Sendable (MTLCommandBuffer) -> Void)? = nil) {
        guard let cb = queue.makeCommandBuffer() else { return }
        refreshVideos(into: cb)
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        var u = makeUniforms(width: width, height: height, original: original, outlines: outlines)
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

    // MARK: Videos

    private var lastDraw = 0.0
    private var idleTimer: Timer?

    /// Videos on screen play and copy in their newest frame; a preloaded one waits paused until its fade.
    /// When nothing has drawn for a second (desktop hidden, window closed, display asleep) they all pause.
    private func refreshVideos(into cb: MTLCommandBuffer) {
        lastDraw = CACurrentMediaTime()
        for v in [current.video, incoming?.video].compactMap({ $0 }) {
            v.setPaused(false)
            v.update(into: cb)
        }
        pending?.0.video?.setPaused(true)
        guard current.video != nil || incoming?.video != nil, idleTimer == nil else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let videos = [self.current.video, self.incoming?.video].compactMap { $0 }
                if videos.isEmpty { timer.invalidate(); self.idleTimer = nil; return }
                if CACurrentMediaTime() - self.lastDraw > 1 { videos.forEach { $0.setPaused(true) } }
            }
        }
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
        if VideoFiles.isVideo(a) {
            // Offscreen checks of the video path: load it off the main thread, keeping the main run loop turning
            // (AVPlayer needs it) until it is ready.
            nonisolated(unsafe) var loaded: Result<PhotoTexture, Error>?
            let ref = PhotoRef(id: UUID(), source: .file(a)), queue = self.queue
            Task.detached {
                do { loaded = .success(try await PhotoLoader.texture(for: ref, queue: queue)) } catch { loaded = .failure(error) }
            }
            while loaded == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
            current = try loaded!.get()
            return
        }
        current = try TextureFactory.load(url: a, queue: queue)
        if let b {
            incoming = try TextureFactory.load(url: b, queue: queue)
            activeStyle = style
            transitionSeconds = 1
            fadeSeconds = 1
            transitionClock = progress
        }
    }

    func snapshot(width: Int, height: Int, outlines: Bool = false, original: Bool = false) -> CGImage? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        guard let target = device.makeTexture(descriptor: desc) else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let sem = DispatchSemaphore(value: 0)
        encode(into: pass, drawable: nil, width: Double(width), height: Double(height), original: original, outlines: outlines) { _ in sem.signal() }
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
    /// Fraction of the Retina pixel density to draw at (the desktop draws lighter to keep the Mac cool).
    var renderScale: CGFloat = 1
    var suspended = false { didSet { refreshPause() } }
    var isPaused: Bool { link?.isPaused ?? true }
    /// Preview only: show the photo itself instead of the kaleidoscope.
    var showOriginal = false
    /// Preview only: trace the pattern's mirror and tile lines in red.
    var showOutlines = false
    /// Preview only: dragging moves the photo inside the mirrors (and keeps gliding after release).
    var acceptsDrag = false
    /// Preview only: a plain click (no real drag) on the picture, e.g. to fill the window with it.
    var onClick: (() -> Void)?
    private var pressAt: (point: NSPoint, time: TimeInterval, travel: CGFloat)?

    override func mouseDown(with event: NSEvent) {
        guard acceptsDrag || onClick != nil else { return super.mouseDown(with: event) }
        pressAt = (event.locationInWindow, event.timestamp, 0)
        if acceptsDrag {
            MainActor.assumeIsolated { renderer.beginDrag() }
            NSCursor.closedHand.push()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard acceptsDrag || onClick != nil else { return super.mouseDragged(with: event) }
        pressAt?.travel += hypot(event.deltaX, event.deltaY)
        guard acceptsDrag, bounds.height > 0 else { return }
        // Points to screen heights; AppKit's y already points up, like the shader's.
        let d = SIMD2<Double>(event.deltaX, -event.deltaY) / Double(bounds.height)
        MainActor.assumeIsolated { renderer.drag(by: d) }
    }

    override func mouseUp(with event: NSEvent) {
        guard acceptsDrag || onClick != nil else { return super.mouseUp(with: event) }
        if acceptsDrag {
            MainActor.assumeIsolated { renderer.endDrag() }
            NSCursor.pop()
        }
        // A click is a quick press that barely moved; anything more was a drag of the photo.
        if let p = pressAt, p.travel < 4, event.timestamp - p.time < 0.4, event.clickCount <= 1 { onClick?() }
        pressAt = nil
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
        // While the view is being resized (e.g. sliding into full window) the last frame fills and crops until
        // the next one is drawn at the new size, instead of stretching.
        layer?.contentsGravity = .resizeAspectFill
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
        let scale = (window?.backingScaleFactor ?? 2) * renderScale
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
            renderer.encode(into: pass, drawable: nil, width: Double(pixelWidth), height: Double(pixelHeight), original: showOriginal, outlines: showOutlines && !showOriginal) { [weak self] cb in
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
