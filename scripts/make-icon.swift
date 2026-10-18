// Renders the 1024px app icon PNG from Resources/icon-source.png, a screenshot of Kaleido itself: the
// mandala is cropped around its centre of symmetry, set in the macOS rounded tile, with a soft glow.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let source = NSImage(contentsOfFile: "Resources/icon-source.png")!
let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil)!
// Centre of the mandala's 5-fold symmetry in the source (found by matching 72° rotations).
let center = CGPoint(x: 956, y: 918)
let radius: CGFloat = 640

let px = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
ctx.interpolationQuality = .high

// Body, inset to Apple's icon grid (824pt square in a 1024 canvas).
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

ctx.saveGState()
let shadow = NSShadow()
shadow.shadowColor = NSColor(white: 0, alpha: 0.3)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
NSColor(srgbRed: 0.05, green: 0.18, blue: 0.06, alpha: 1).setFill()
shape.fill()
ctx.restoreGState()

ctx.saveGState()
shape.addClip()
// Crop a square around the centre (CGImage crops use a top-left origin) and fill the tile with it.
let crop = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
ctx.draw(cg.cropping(to: crop)!, in: body)
// Gentle vignette pulls the eye to the centre and hides the busy screenshot edges.
let vignette = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [NSColor(white: 0, alpha: 0).cgColor, NSColor(white: 0, alpha: 0.55).cgColor] as CFArray,
                          locations: [0.6, 1])!
ctx.drawRadialGradient(vignette, startCenter: CGPoint(x: 512, y: 512), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 512), endRadius: 590, options: [.drawsAfterEndLocation])
// Faint top highlight, like the system icons.
NSGradient(starting: NSColor(white: 1, alpha: 0.14), ending: NSColor(white: 1, alpha: 0))!
    .draw(in: NSRect(x: 100, y: 600, width: 824, height: 324), angle: -90)
ctx.restoreGState()

NSColor(white: 1, alpha: 0.18).setStroke()
let rim = NSBezierPath(roundedRect: body.insetBy(dx: 1, dy: 1), xRadius: 184, yRadius: 184)
rim.lineWidth = 2
rim.stroke()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
