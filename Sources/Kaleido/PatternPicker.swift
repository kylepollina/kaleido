import KaleidoCore
import SwiftUI

/// The pattern (mirror mode) chooser in the preset editor: a grid of buttons, each with a small line drawing
/// of the pattern's mirrors and its name.
struct PatternPicker: View {
    @Binding var selection: MirrorMode
    private let columns = [GridItem(.adaptive(minimum: 92, maximum: 120), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(MirrorMode.allCases) { mode in
                let selected = mode == selection
                Button { selection = mode } label: {
                    VStack(spacing: 4) {
                        PatternIcon(mode: mode)
                            .stroke(selected ? Color.accentColor : Color.primary.opacity(0.7), lineWidth: 1.3)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Text(mode.label).font(.caption).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(mode.label)
            }
        }
    }
}

/// Vector line drawings of each pattern's mirror lines, scaled to whatever frame they are given.
struct PatternIcon: Shape {
    let mode: MirrorMode

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        func line(_ a: CGPoint, _ b: CGPoint) { p.move(to: a); p.addLine(to: b) }
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        func rays(_ n: Int, radius: CGFloat, offset: CGFloat = 0) {
            for i in 0..<n {
                let a = offset + CGFloat(i) * 2 * .pi / CGFloat(n)
                line(c, CGPoint(x: c.x + cos(a) * radius, y: c.y + sin(a) * radius))
            }
        }

        switch mode {
        case .radial:
            rays(8, radius: s * 0.48)
            p.addEllipse(in: CGRect(x: c.x - s * 0.3, y: c.y - s * 0.3, width: s * 0.6, height: s * 0.6))
        case .fractal:
            rays(5, radius: s * 0.48, offset: -.pi / 2)
            for r in [0.42, 0.26, 0.12] as [CGFloat] {
                var star = Path()
                for i in 0..<10 {
                    let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
                    let rr = i % 2 == 0 ? r * s : r * s * 0.45
                    let q = CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr)
                    i == 0 ? star.move(to: q) : star.addLine(to: q)
                }
                star.closeSubpath()
                p.addPath(star)
            }
        case .hex, .cubes:
            // A centre hexagon and its six neighbours (pointy-top), with the cube edges for Diamonds.
            let r = s * 0.21
            let w = r * sqrt(3)
            let centres = [CGPoint(x: 0, y: 0), CGPoint(x: w, y: 0), CGPoint(x: -w, y: 0),
                           CGPoint(x: w / 2, y: r * 1.5), CGPoint(x: -w / 2, y: r * 1.5),
                           CGPoint(x: w / 2, y: -r * 1.5), CGPoint(x: -w / 2, y: -r * 1.5)]
            for o in centres {
                let h = CGPoint(x: c.x + o.x, y: c.y + o.y)
                var hex = Path()
                for i in 0..<6 {
                    let a = CGFloat.pi / 6 + CGFloat(i) * .pi / 3
                    let q = CGPoint(x: h.x + cos(a) * r, y: h.y + sin(a) * r)
                    i == 0 ? hex.move(to: q) : hex.addLine(to: q)
                }
                hex.closeSubpath()
                p.addPath(hex)
                for i in 0..<3 {
                    let a = (mode == .cubes ? -CGFloat.pi / 2 : CGFloat.pi / 6) + CGFloat(i) * 2 * .pi / 3
                    if mode == .cubes {
                        line(h, CGPoint(x: h.x + cos(a) * r, y: h.y + sin(a) * r))
                    } else if o == .zero {
                        // Hex mirrors: six lines through the centre cell.
                        line(CGPoint(x: h.x - cos(a) * r, y: h.y - sin(a) * r), CGPoint(x: h.x + cos(a) * r, y: h.y + sin(a) * r))
                    }
                }
            }
        case .square:
            for i in 0...3 {
                let t = CGFloat(i) / 3
                line(pt(t, 0), pt(t, 1)); line(pt(0, t), pt(1, t))
            }
            for i in 0..<3 { for j in 0..<3 {
                let x = CGFloat(i) / 3, y = CGFloat(j) / 3, d: CGFloat = 1 / 3
                line(pt(x, y), pt(x + d, y + d)); line(pt(x + d, y), pt(x, y + d))
            } }
        case .grid:
            for i in 0...3 { let t = CGFloat(i) / 3; line(pt(t, 0), pt(t, 1)) }
            for i in 0...4 { let t = CGFloat(i) / 4; line(pt(0, t), pt(1, t)) }
        case .spiral:
            rays(6, radius: s * 0.5)
            var r = s * 0.06
            while r < s * 0.5 {
                p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                r *= 1.7
            }
        case .triangle:
            let h = s * sqrt(3) / 2 / 3
            for row in -1...4 {
                let y = rect.minY + CGFloat(row) * h
                line(CGPoint(x: rect.minX, y: y), CGPoint(x: rect.maxX, y: y))
            }
            for k in -4...6 {
                let x0 = rect.minX + CGFloat(k) * s / 3
                line(CGPoint(x: x0, y: rect.minY), CGPoint(x: x0 + s / sqrt(3), y: rect.minY + s))
                line(CGPoint(x: x0, y: rect.minY), CGPoint(x: x0 - s / sqrt(3), y: rect.minY + s))
            }
        }
        return p
    }
}
