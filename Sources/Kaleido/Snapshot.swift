import AppKit
import KaleidoCore
import UniformTypeIdentifiers

/// `Kaleido --snapshot out.png --photo a.jpg [--photo2 b.jpg --mix 0.5 --transition iris]
///  [--mode radial|hex|fractal] [--segments 8] [--zoom 1] [--time 12] [--size 1280x720] [--twist 0] [--hue 0]`
/// Renders one frame offscreen with the real shader and exits. Needs no window or screen-recording permission.
enum Snapshot {
    @MainActor
    static func runAndExit() -> Never {
        let args = CommandLine.arguments
        func value(_ name: String) -> String? {
            guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        guard let out = value("--snapshot"), let photo = value("--photo"), let renderer = KaleidoRenderer() else {
            FileHandle.standardError.write(Data("usage: Kaleido --snapshot out.png --photo file [options]\n".utf8))
            exit(2)
        }
        var look = Look()
        if let m = value("--mode"), let mode = MirrorMode(rawValue: m) { look.mode = mode }
        if let s = value("--segments").flatMap(Int.init) { look.segments = s }
        if let z = value("--zoom").flatMap(Double.init) { look.zoom = z }
        if let t = value("--twist").flatMap(Double.init) { look.twist = t }
        if let o = value("--outline").flatMap(Double.init) { look.outline = o }
        if let h = value("--hue").flatMap(Double.init) { look.hueShift = h }
        if let s = value("--sat").flatMap(Double.init) { look.saturation = s }
        look.clamp()
        renderer.targetLook = look
        renderer.snapLook()
        var size = (w: 1280, h: 720)
        if let parts = value("--size")?.split(separator: "x").compactMap({ Int($0) }), parts.count == 2 { size = (parts[0], parts[1]) }
        do {
            let style = value("--transition").flatMap(TransitionStyle.init(rawValue:)) ?? .dissolve
            let photo2 = value("--photo2").map { URL(fileURLWithPath: $0) }
            try renderer.setPhotosImmediately(URL(fileURLWithPath: photo), photo2, progress: value("--mix").flatMap(Double.init) ?? 0.5, style: style)
            if let to = value("--morph-to").flatMap(Int.init) {
                renderer.forceMorph(to: to, progress: value("--morph").flatMap(Double.init) ?? 0.5)
            }
            let seconds = value("--time").flatMap(Double.init) ?? 0
            if photo2 == nil {
                var t = 0.0
                while t < seconds { renderer.advance(1.0 / 30); t += 1.0 / 30 }
            }
        } catch {
            FileHandle.standardError.write(Data("load failed: \(error)\n".utf8))
            exit(1)
        }
        guard let image = renderer.snapshot(width: size.w, height: size.h, outlines: args.contains("--outlines"),
                                            original: args.contains("--original")),
              let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { exit(1) }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        print("wrote \(out)")
        exit(0)
    }
}

/// `Kaleido --stress-render dir [--seconds 600] [--per-photo 10]`: plays every photo and video in `dir` through the
/// real renderer off screen (1920x1080, 30 fps), changing photo every few seconds, and logs memory now and then.
/// For hunting leaks and heat without putting anything on the desktop.
@MainActor
final class StressRender: PhotoProvider {
    private let refs: [PhotoRef]
    private var index = 0

    init(files: [URL]) { refs = files.map { PhotoRef(id: UUID(), source: .file($0)) } }

    func nextPhoto(after current: UUID?) -> PhotoRef? {
        guard !refs.isEmpty else { return nil }
        index = (index + 1) % refs.count
        return refs[index]
    }

    static func run(dir: String, seconds: Double, perPhoto: Double) {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil)) ?? [])
            .filter { ImageFiles.isSupported($0) || VideoFiles.isVideo($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard let renderer = KaleidoRenderer(), !files.isEmpty else {
            FileHandle.standardError.write(Data("stress: no renderer or no files in \(dir)\n".utf8)); exit(2)
        }
        let provider = StressRender(files: files)
        renderer.provider = provider
        renderer.secondsPerPhoto = perPhoto
        renderer.transitionSeconds = 2
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1920, height: 1080, mipmapped: false)
        desc.usage = [.renderTarget]
        desc.storageMode = .private
        nonisolated(unsafe) let target = renderer.device.makeTexture(descriptor: desc)!
        let start = CACurrentMediaTime()
        var frames = 0, lastLog = start
        print("stress: \(files.count) files (\(files.filter(VideoFiles.isVideo).count) videos), \(Int(seconds)) s")
        Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { _ in
            MainActor.assumeIsolated {
                let now = CACurrentMediaTime()
                renderer.tick(now: now)
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = target
                pass.colorAttachments[0].loadAction = .dontCare
                pass.colorAttachments[0].storeAction = .store
                renderer.encode(into: pass, drawable: nil, width: 1920, height: 1080)
                frames += 1
                if now - lastLog >= 30 {
                    lastLog = now
                    print(String(format: "stress: t=%4.0fs frames=%d footprint=%.0f MB", now - start, frames, StressRender.footprintMB()))
                }
                if now - start >= seconds { exit(0) }
            }
        }
        RunLoop.main.run()
    }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }
}
