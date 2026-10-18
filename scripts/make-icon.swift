// Renders the 1024px app icon PNG: a twelve-fold kaleidoscope rosette on a dark tile.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let px = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
ctx.saveGState()
let shadow = NSShadow()
shadow.shadowColor = rgb(0, 0, 0, 0.3)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
rgb(14, 18, 40).setFill()
shape.fill()
ctx.restoreGState()
shape.addClip()
NSGradient(starting: rgb(36, 28, 84), ending: rgb(8, 12, 30))!.draw(in: shape, angle: -90)

let c = CGPoint(x: 512, y: 512)
let n = 12
let seg = 2 * CGFloat.pi / CGFloat(n)
// Wedge content: a few translucent petals; mirrored on alternate wedges so seams vanish.
let petals: [(CGFloat, CGFloat, CGFloat, NSColor)] = [
    (330, 0.50, 120, rgb(255, 120, 90, 0.95)),
    (250, 0.30, 95, rgb(255, 200, 80, 0.9)),
    (170, 0.62, 80, rgb(90, 220, 200, 0.9)),
    (95, 0.35, 60, rgb(160, 110, 255, 0.95)),
    (395, 0.22, 70, rgb(80, 170, 255, 0.85)),
]
for i in 0..<n {
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    if i % 2 == 1 {
        ctx.rotate(by: CGFloat(i + 1) * seg)
        ctx.scaleBy(x: 1, y: -1)
    } else {
        ctx.rotate(by: CGFloat(i) * seg)
    }
    let wedge = CGMutablePath()
    wedge.move(to: .zero)
    wedge.addLine(to: CGPoint(x: 520, y: 0))
    wedge.addArc(center: .zero, radius: 520, startAngle: 0, endAngle: seg, clockwise: false)
    wedge.closeSubpath()
    ctx.addPath(wedge)
    ctx.clip()
    for (dist, ang, r, color) in petals {
        let pt = CGPoint(x: cos(ang * seg) * dist, y: sin(ang * seg) * dist)
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: pt, startRadius: 0, endCenter: pt, endRadius: r, options: [])
    }
    ctx.restoreGState()
}
let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [rgb(255, 255, 255, 0.85).cgColor, rgb(255, 255, 255, 0).cgColor] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: c, startRadius: 0, endCenter: c, endRadius: 90, options: [])

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
