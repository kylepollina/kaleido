import Foundation

public enum MirrorMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case radial, hex, fractal, square, grid, spiral, triangle, cubes
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .radial: return "Classic"
        case .hex: return "Hex"
        case .fractal: return "Fractal"
        case .square: return "Square"
        case .grid: return "Mirror grid"
        case .spiral: return "Spiral"
        case .triangle: return "Triangle"
        case .cubes: return "Diamonds"
        }
    }
    public var shaderIndex: Int32 {
        switch self {
        case .radial: return 0
        case .hex: return 1
        case .fractal: return 2
        case .square: return 3
        case .grid: return 4
        case .spiral: return 5
        case .triangle: return 6
        case .cubes: return 7
        }
    }
    /// Repeating tilings, where `segments` sets how dense the tiles are rather than a mirror count.
    public var isTiling: Bool { [.hex, .square, .grid, .triangle, .cubes].contains(self) }
    /// What the `segments` slider means in this mode.
    public var countLabel: String {
        switch self {
        case .hex, .square, .grid, .triangle, .cubes: return "Tile density"
        case .spiral: return "Spiral arms"
        default: return "Mirrors"
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MirrorMode(rawValue: raw) ?? .radial
    }
}

public enum TransitionStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    // The angular "swirl wipe" and the dizzying "spin" were removed; old settings that name them load as random.
    case random, dissolve, iris, zoom, segments
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .random: return "Random"
        case .dissolve: return "Dissolve"
        case .iris: return "Iris"
        case .zoom: return "Zoom through"
        case .segments: return "Segment ripple"
        }
    }
    /// Index used by the shader. `.random` has none; the renderer picks a concrete style per transition.
    public var shaderIndex: Int32 {
        switch self {
        case .random, .dissolve: return 0
        case .iris: return 1
        case .zoom: return 3
        case .segments: return 4
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TransitionStyle(rawValue: raw) ?? .random
    }
    public static var concrete: [TransitionStyle] { allCases.filter { $0 != .random } }
}

/// Everything that shapes how the kaleidoscope looks. Cheap to copy; the renderer eases toward a new
/// `Look` so slider drags and preset changes glide instead of jumping.
public struct Look: Codable, Equatable, Sendable {
    public var mode: MirrorMode = .radial
    /// Mirror segments around the center (radial/fractal) or tile density (hex).
    public var segments: Int = 12
    /// Degrees per second the mirror pattern turns. Barely-moving range: +-0.6, default one turn per 100 minutes.
    public var rotationSpeed: Double = 0.06
    /// Magnification of the photo inside the mirrors.
    public var zoom: Double = 1.0
    /// 0...1 how far the sampled window wanders across the photo.
    public var drift: Double = 1.0
    /// How fast it wanders (0.5, the maximum, is a lap in about 5 minutes; the default takes half an hour).
    public var driftSpeed: Double = 0.08
    /// Swirl: bends the mirrors with distance from the center, in radians per screen height.
    public var twist: Double = 0
    /// Swirl sways back and forth (through straight and the other way) instead of holding still.
    public var swayingSwirl = false
    /// Static hue rotation in degrees.
    public var hueShift: Double = 0
    /// Degrees per second the hue keeps rotating (at most 0.6: a full cycle in 10 minutes).
    public var hueSpeed: Double = 0
    public var saturation: Double = 1.1
    public var vignette: Double = 0.35
    /// 0...1 how far the zoom slowly breathes in and out (about a ten minute cycle).
    public var breathing: Double = 1.0
    /// Master multiplier for every speed above: 0 is perfectly still, 1 is as set, up to 2.
    public var motion: Double = 1.0
    /// Dynamic mirrors: the mirror count (or tile density) wanders one step at a time between these bounds,
    /// cross-fading between counts so the pattern never snaps.
    /// Black lines along every mirror and tile edge: one of `outlineSteps` (0 = off, 0.25 = on).
    public var outline: Double = 0
    public static let outlineSteps: [Double] = [0, 0.25]
    /// Hue cycling choices in degrees per second: off, slow, medium, fast.
    public static let hueCycleSteps: [Double] = [0, 0.05, 0.15, 0.4]
    /// Diamonds pattern only: true ("Checker") gives each diamond orientation its own part of the photo and
    /// turning direction; false ("Mirror") makes every diamond the same.
    public var checkerFaces = false
    public var dynamicMirrors = false
    public var mirrorsMin = 4
    public var mirrorsMax = 12

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
        swayingSwirl = try c.decodeIfPresent(Bool.self, forKey: .swayingSwirl) ?? d.swayingSwirl
        hueShift = try c.decodeIfPresent(Double.self, forKey: .hueShift) ?? d.hueShift
        hueSpeed = try c.decodeIfPresent(Double.self, forKey: .hueSpeed) ?? d.hueSpeed
        saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? d.saturation
        vignette = try c.decodeIfPresent(Double.self, forKey: .vignette) ?? d.vignette
        breathing = try c.decodeIfPresent(Double.self, forKey: .breathing) ?? d.breathing
        motion = try c.decodeIfPresent(Double.self, forKey: .motion) ?? d.motion
        outline = try c.decodeIfPresent(Double.self, forKey: .outline) ?? d.outline
        checkerFaces = try c.decodeIfPresent(Bool.self, forKey: .checkerFaces) ?? d.checkerFaces
        dynamicMirrors = try c.decodeIfPresent(Bool.self, forKey: .dynamicMirrors) ?? d.dynamicMirrors
        mirrorsMin = try c.decodeIfPresent(Int.self, forKey: .mirrorsMin) ?? d.mirrorsMin
        mirrorsMax = try c.decodeIfPresent(Int.self, forKey: .mirrorsMax) ?? d.mirrorsMax
        clamp()
    }

    public static let segmentRange = 2...24

    /// Keeps hand-edited or old files inside the ranges the shader is written for.
    public mutating func clamp() {
        segments = min(max(segments, Self.segmentRange.lowerBound), Self.segmentRange.upperBound)
        rotationSpeed = min(max(rotationSpeed, -0.6), 0.6)
        zoom = min(max(zoom, 0.4), 3)
        drift = min(max(drift, 0), 1)
        driftSpeed = min(max(driftSpeed, 0), 0.5)
        twist = min(max(twist, -1), 1)
        let h = hueSpeed
        hueSpeed = Self.hueCycleSteps.min { abs($0 - h) < abs($1 - h) }!
        breathing = min(max(breathing, 0), 1)
        motion = min(max(motion, 0), 2)
        let o = outline
        outline = Self.outlineSteps.min { abs($0 - o) < abs($1 - o) }!
        let r = Self.segmentRange
        mirrorsMin = min(max(mirrorsMin, r.lowerBound), r.upperBound)
        mirrorsMax = min(max(mirrorsMax, r.lowerBound), r.upperBound)
        if mirrorsMin > mirrorsMax { swap(&mirrorsMin, &mirrorsMax) }
        saturation = min(max(saturation, 0.5), 1.5)
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
        r.hueShift = l(hueShift, target.hueShift)
        r.hueSpeed = l(hueSpeed, target.hueSpeed)
        r.saturation = l(saturation, target.saturation)
        r.vignette = l(vignette, target.vignette)
        r.breathing = l(breathing, target.breathing)
        r.motion = l(motion, target.motion)
        return r
    }

    /// A random but good-looking look: weighted toward values that tend to read as a kaleidoscope.
    public static func random<G: RandomNumberGenerator>(using g: inout G) -> Look {
        var l = Look()
        // Classic is still the most likely; the tilings and the spiral show up for variety.
        let modes: [(MirrorMode, Double)] = [(.radial, 0.40), (.hex, 0.10), (.fractal, 0.10), (.square, 0.10), (.grid, 0.05),
                                             (.spiral, 0.09), (.triangle, 0.09), (.cubes, 0.07)]
        var roll = Double.random(in: 0..<1, using: &g)
        l.mode = modes.first { roll -= $0.1; return roll < 0 }?.0 ?? .radial
        switch l.mode {
        case .hex, .square, .grid, .triangle, .cubes: l.segments = Int.random(in: 3...9, using: &g)
        case .fractal: l.segments = [3, 4, 5, 6, 8].randomElement(using: &g)!
        case .spiral: l.segments = [2, 4, 6, 8].randomElement(using: &g)!
        case .radial: l.segments = [3, 4, 5, 6, 6, 7, 8, 8, 9, 10, 12, 14, 16].randomElement(using: &g)!
        }
        l.rotationSpeed = Double.random(in: 0.02...0.15, using: &g) * (Bool.random(using: &g) ? 1 : -1)
        l.driftSpeed = Double.random(in: 0.03...0.15, using: &g)
        l.twist = Double.random(in: 0..<1, using: &g) < 0.3 ? Double.random(in: -0.4...0.4, using: &g) : 0
        l.hueShift = Double.random(in: 0..<1, using: &g) < 0.4 ? Double.random(in: 0...360, using: &g) : 0
        l.hueSpeed = Double.random(in: 0..<1, using: &g) < 0.3 ? [0.05, 0.15].randomElement(using: &g)! : 0
        l.saturation = Double.random(in: 0.95...1.4, using: &g)
        l.vignette = Double.random(in: 0.1...0.45, using: &g)
        l.outline = Double.random(in: 0..<1, using: &g) < 0.15 ? 0.25 : 0
        if (l.mode == .radial || l.mode == .fractal) && Double.random(in: 0..<1, using: &g) < 0.25 {
            l.dynamicMirrors = true
            l.mirrorsMin = max(3, l.segments - 3)
            l.mirrorsMax = min(Self.segmentRange.upperBound, l.segments + 4)
        }
        l.clamp()
        return l
    }

    /// The next mirror count for dynamic mirrors: one step up or down, staying inside the range
    /// (a count outside it heads back in).
    public static func nextMirrorCount<G: RandomNumberGenerator>(from n: Int, min lo: Int, max hi: Int, using g: inout G) -> Int {
        if lo >= hi { return lo }
        if n < lo { return n + 1 }
        if n > hi { return n - 1 }
        if n == lo { return n + 1 }
        if n == hi { return n - 1 }
        return Bool.random(using: &g) ? n + 1 : n - 1
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

    /// A preset other than the one currently showing (when there is a choice).
    public static func random<G: RandomNumberGenerator>(excluding current: Look?, using g: inout G) -> Preset {
        let choices = all.filter { $0.look != current }
        return (choices.isEmpty ? all : choices).randomElement(using: &g)!
    }

    public static func random(excluding current: Look?) -> Preset {
        var g = SystemRandomNumberGenerator()
        return random(excluding: current, using: &g)
    }

    public static let all: [Preset] = {
        func make(_ name: String, _ edit: (inout Look) -> Void) -> Preset {
            var l = Look()
            edit(&l)
            l.clamp()
            return Preset(name: name, look: l)
        }
        return [
            // One or two per pattern. Zoom, drift and zoom breathing stay at 100% (the defaults) throughout.
            make("Mandala") { _ in },
            make("Shifting Mandala") {
                $0.segments = 8; $0.dynamicMirrors = true; $0.mirrorsMin = 6; $0.mirrorsMax = 14; $0.vignette = 0.3
            },
            make("Ink Mandala") {
                $0.segments = 10; $0.outline = Look.outlineSteps[1]; $0.rotationSpeed = 0.05; $0.vignette = 0.2
            },
            make("Whirlpool") {
                $0.segments = 7; $0.twist = 0.6; $0.swayingSwirl = true; $0.rotationSpeed = -0.08
            },
            make("Prism") {
                $0.segments = 16; $0.hueSpeed = Look.hueCycleSteps[1]; $0.saturation = 1.3; $0.rotationSpeed = 0.08
            },
            make("Fractal Bloom") {
                $0.mode = .fractal; $0.segments = 5; $0.saturation = 1.2; $0.rotationSpeed = 0.08
            },
            make("Hex Garden") {
                $0.mode = .hex; $0.segments = 5; $0.rotationSpeed = 0.03
            },
            make("Square Tiles") {
                $0.mode = .square; $0.segments = 4; $0.rotationSpeed = 0.03
            },
            make("Hall of Mirrors") {
                $0.mode = .grid; $0.segments = 4; $0.rotationSpeed = 0.02; $0.vignette = 0.25
            },
            make("Triangle Toy") {
                $0.mode = .triangle; $0.segments = 4; $0.rotationSpeed = 0.04
            },
            make("Diamonds") {
                $0.mode = .cubes; $0.segments = 4; $0.rotationSpeed = 0.02
            },
            make("Checker Diamonds") {
                $0.mode = .cubes; $0.segments = 4; $0.checkerFaces = true; $0.outline = Look.outlineSteps[1]
                $0.rotationSpeed = 0.02
            },
            make("Spiral Tunnel") {
                $0.mode = .spiral; $0.segments = 6; $0.vignette = 0.45; $0.rotationSpeed = 0.06
            },
        ]
    }()
}
