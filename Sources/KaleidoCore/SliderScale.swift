import Foundation

/// Maps a 0...1 slider position to a value. Logarithmic scales give fine control at the slow end.
public enum SliderScale: Sendable {
    case linear(Double, Double)
    /// Logarithmic from `min` (position 0) to `max` (position 1); both must be positive.
    case log(Double, Double)
    /// Position 0...1 spans -max...max with a flat zero in the middle; each side is logarithmic from `min`.
    case signedLog(min: Double, max: Double)
    /// Position 0 is exactly 0 (still); above a small dead zone it runs logarithmically from `min` to `max`.
    case zeroLog(min: Double, max: Double)
    /// `mid` sits exactly in the middle of the slider; each half is logarithmic (for multipliers around 1).
    case centeredLog(min: Double, mid: Double, max: Double)

    /// Fraction of the signed scale (each side) that is the "zero" dead zone.
    private static let dead = 0.04

    public func value(at t: Double) -> Double {
        let t = Swift.min(Swift.max(t, 0), 1)
        switch self {
        case let .linear(a, b): return a + (b - a) * t
        case let .log(a, b): return a * pow(b / a, t)
        case let .zeroLog(a, b):
            if t < Self.dead { return 0 }
            return a * pow(b / a, (t - Self.dead) / (1 - Self.dead))
        case let .centeredLog(a, mid, b):
            return t < 0.5 ? a * pow(mid / a, t * 2) : mid * pow(b / mid, (t - 0.5) * 2)
        case let .signedLog(a, b):
            let u = t * 2 - 1
            let m = abs(u)
            if m <= Self.dead { return 0 }
            let v = a * pow(b / a, (m - Self.dead) / (1 - Self.dead))
            return u < 0 ? -v : v
        }
    }

    public func position(for v: Double) -> Double {
        switch self {
        case let .linear(a, b): return Swift.min(Swift.max((v - a) / (b - a), 0), 1)
        case let .log(a, b): return Swift.min(Swift.max(Foundation.log(Swift.max(v, a) / a) / Foundation.log(b / a), 0), 1)
        case let .zeroLog(a, b):
            if v < a * 0.5 { return 0 }
            let frac = Swift.min(Swift.max(Foundation.log(Swift.max(v, a) / a) / Foundation.log(b / a), 0), 1)
            return Self.dead + frac * (1 - Self.dead)
        case let .centeredLog(a, mid, b):
            let v = Swift.min(Swift.max(v, a), b)
            return v < mid ? Foundation.log(v / a) / Foundation.log(mid / a) / 2
                           : 0.5 + Foundation.log(v / mid) / Foundation.log(b / mid) / 2
        case let .signedLog(a, b):
            let m = abs(v)
            if m < a * 0.5 { return 0.5 }
            let frac = Swift.min(Swift.max(Foundation.log(Swift.max(m, a) / a) / Foundation.log(b / a), 0), 1)
            let u = Self.dead + frac * (1 - Self.dead)
            return v < 0 ? (1 - u) / 2 : (1 + u) / 2
        }
    }
}
