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
