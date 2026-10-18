import Foundation

public enum MirrorMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case radial, hex, fractal
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .radial: return "Classic"
        case .hex: return "Tiled hex"
        case .fractal: return "Fractal"
        }
    }
    public var shaderIndex: Int32 {
        switch self {
        case .radial: return 0
        case .hex: return 1
        case .fractal: return 2
        }
    }
}

public enum TransitionStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case random, dissolve, iris, swirl, zoom, segments, spin
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .random: return "Random"
        case .dissolve: return "Dissolve"
        case .iris: return "Iris"
        case .swirl: return "Swirl wipe"
        case .zoom: return "Zoom through"
        case .segments: return "Segment ripple"
        case .spin: return "Spin"
        }
    }
    /// Index used by the shader. `.random` has none; the renderer picks a concrete style per transition.
    public var shaderIndex: Int32 {
        switch self {
        case .random, .dissolve: return 0
        case .iris: return 1
        case .swirl: return 2
        case .zoom: return 3
        case .segments: return 4
        case .spin: return 5
        }
    }
    public static var concrete: [TransitionStyle] { allCases.filter { $0 != .random } }
}

/// Everything that shapes how the kaleidoscope looks. Cheap to copy; the renderer eases toward a new
/// `Look` so slider drags and preset changes glide instead of jumping.
public struct Look: Codable, Equatable, Sendable {
    public var mode: MirrorMode = .radial
    /// Mirror segments around the center (radial/fractal) or tile density (hex).
    public var segments: Int = 8
    /// Degrees per second the mirror pattern turns.
    public var rotationSpeed: Double = 6
    /// Magnification of the photo inside the mirrors.
    public var zoom: Double = 1.0
    /// 0...1 how far the sampled window wanders across the photo.
    public var drift: Double = 0.35
    /// How fast it wanders (1 = a slow lap every minute or so).
    public var driftSpeed: Double = 1.0
    /// Swirl: bends the mirrors with distance from the center, in radians per screen height.
    public var twist: Double = 0
    /// 0...1 softness (samples blurrier mip levels).
    public var blur: Double = 0
    /// Static hue rotation in degrees.
    public var hueShift: Double = 0
    /// Degrees per second the hue keeps rotating.
    public var hueSpeed: Double = 0
    public var saturation: Double = 1.1
    public var vignette: Double = 0.25

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Look()
        mode = try c.decodeIfPresent(MirrorMode.self, forKey: .mode) ?? d.mode
        segments = try c.decodeIfPresent(Int.self, forKey: .segments) ?? d.segments
        rotationSpeed = try c.decodeIfPresent(Double.self, forKey: .rotationSpeed) ?? d.rotationSpeed
        zoom = try c.decodeIfPresent(Double.self, forKey: .zoom) ?? d.zoom
        drift = try c.decodeIfPresent(Double.self, forKey: .drift) ?? d.drift
        driftSpeed = try c.decodeIfPresent(Double.self, forKey: .driftSpeed) ?? d.driftSpeed
        twist = try c.decodeIfPresent(Double.self, forKey: .twist) ?? d.twist
        blur = try c.decodeIfPresent(Double.self, forKey: .blur) ?? d.blur
        hueShift = try c.decodeIfPresent(Double.self, forKey: .hueShift) ?? d.hueShift
        hueSpeed = try c.decodeIfPresent(Double.self, forKey: .hueSpeed) ?? d.hueSpeed
        saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? d.saturation
        vignette = try c.decodeIfPresent(Double.self, forKey: .vignette) ?? d.vignette
        clamp()
    }

    public static let segmentRange = 2...24

    /// Keeps hand-edited or old files inside the ranges the shader is written for.
    public mutating func clamp() {
        segments = min(max(segments, Self.segmentRange.lowerBound), Self.segmentRange.upperBound)
        zoom = min(max(zoom, 0.25), 4)
        drift = min(max(drift, 0), 1)
        driftSpeed = min(max(driftSpeed, 0), 5)
        blur = min(max(blur, 0), 1)
        saturation = min(max(saturation, 0), 2)
        vignette = min(max(vignette, 0), 1)
    }

    /// Moves continuous values `k` (0...1) of the way toward `target`; discrete ones switch at once.
    public func eased(toward target: Look, by k: Double) -> Look {
        func l(_ a: Double, _ b: Double) -> Double { a + (b - a) * k }
        var r = target
        r.rotationSpeed = l(rotationSpeed, target.rotationSpeed)
        r.zoom = exp(l(log(zoom), log(target.zoom)))
        r.drift = l(drift, target.drift)
        r.driftSpeed = l(driftSpeed, target.driftSpeed)
        r.twist = l(twist, target.twist)
        r.blur = l(blur, target.blur)
        r.hueShift = l(hueShift, target.hueShift)
        r.hueSpeed = l(hueSpeed, target.hueSpeed)
        r.saturation = l(saturation, target.saturation)
        r.vignette = l(vignette, target.vignette)
        return r
    }

    /// A random but good-looking look: weighted toward values that tend to read as a kaleidoscope.
    public static func random<G: RandomNumberGenerator>(using g: inout G) -> Look {
        var l = Look()
        let modeRoll = Double.random(in: 0..<1, using: &g)
        l.mode = modeRoll < 0.55 ? .radial : (modeRoll < 0.8 ? .hex : .fractal)
        switch l.mode {
        case .hex: l.segments = Int.random(in: 3...9, using: &g)
        case .fractal: l.segments = [3, 4, 5, 6, 8].randomElement(using: &g)!
        case .radial: l.segments = [3, 4, 5, 6, 6, 7, 8, 8, 9, 10, 12, 14, 16].randomElement(using: &g)!
        }
        l.rotationSpeed = Double.random(in: 2...22, using: &g) * (Bool.random(using: &g) ? 1 : -1)
        l.zoom = Double.random(in: 0.7...2.2, using: &g)
        l.drift = Double.random(in: 0.15...0.8, using: &g)
        l.driftSpeed = Double.random(in: 0.5...2.0, using: &g)
        l.twist = Double.random(in: 0..<1, using: &g) < 0.3 ? Double.random(in: -1.2...1.2, using: &g) : 0
        l.blur = Double.random(in: 0..<1, using: &g) < 0.25 ? Double.random(in: 0.1...0.5, using: &g) : 0
        l.hueShift = Double.random(in: 0..<1, using: &g) < 0.4 ? Double.random(in: 0...360, using: &g) : 0
        l.hueSpeed = Double.random(in: 0..<1, using: &g) < 0.3 ? Double.random(in: 2...14, using: &g) : 0
        l.saturation = Double.random(in: 0.95...1.4, using: &g)
        l.vignette = Double.random(in: 0.1...0.45, using: &g)
        l.clamp()
        return l
    }

    public static func random() -> Look {
        var g = SystemRandomNumberGenerator()
        return random(using: &g)
    }
}

public struct Preset: Identifiable, Equatable, Sendable {
    public let name: String
    public let look: Look
    public var id: String { name }

    public static let all: [Preset] = {
        func make(_ name: String, _ edit: (inout Look) -> Void) -> Preset {
            var l = Look()
            edit(&l)
            l.clamp()
            return Preset(name: name, look: l)
        }
        return [
            make("Classic") { _ in },
            make("Slow Mandala") {
                $0.segments = 12; $0.rotationSpeed = 3; $0.zoom = 1.4; $0.drift = 0.25; $0.driftSpeed = 0.6
                $0.vignette = 0.35
            },
            make("Drifting Hex Garden") {
                $0.mode = .hex; $0.segments = 5; $0.rotationSpeed = 2.5; $0.zoom = 1.1; $0.drift = 0.5
                $0.driftSpeed = 0.8
            },
            make("Fractal Bloom") {
                $0.mode = .fractal; $0.segments = 5; $0.rotationSpeed = 7; $0.zoom = 1.3; $0.drift = 0.45
                $0.saturation = 1.25
            },
            make("Dream Blur") {
                $0.segments = 6; $0.rotationSpeed = 4; $0.zoom = 0.9; $0.blur = 0.45; $0.drift = 0.5
                $0.saturation = 1.3; $0.vignette = 0.4
            },
            make("Prism Spin") {
                $0.segments = 16; $0.rotationSpeed = 14; $0.zoom = 1.8; $0.hueSpeed = 10; $0.saturation = 1.35
            },
            make("Whirlpool") {
                $0.segments = 7; $0.rotationSpeed = -9; $0.twist = 0.9; $0.zoom = 1.2; $0.drift = 0.3
            },
            make("Gentle Window") {
                $0.segments = 3; $0.rotationSpeed = 1.5; $0.zoom = 0.8; $0.drift = 0.6; $0.driftSpeed = 0.5
                $0.vignette = 0.15; $0.saturation = 1.0
            },
        ]
    }()
}
