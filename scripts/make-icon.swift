// Renders the Rankly app icon (1024×1024 PNG) with CoreGraphics.
// Usage: swift scripts/make-icon.swift <output.png> [--flat]
//   --flat  full-bleed square without the macOS squircle/shadow (for the website favicon etc.)
import AppKit

let args = CommandLine.arguments
let out = args.count > 1 ? args[1] : "icon.png"
let flat = args.contains("--flat")
let size: CGFloat = 1024

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

// Brand gradient (keep in sync with Theme.swift and the website).
let brand: [CGColor] = [color(0x4F46E5), color(0x9333EA), color(0xEC4899), color(0xF97316)]

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// macOS icon grid: 824pt squircle centered in 1024 with room for the shadow.
let rect = flat ? CGRect(x: 0, y: 0, width: size, height: size) : CGRect(x: 100, y: 100, width: 824, height: 824)
let radius: CGFloat = flat ? 0 : 185
let shape = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

if !flat {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: color(0x000000, 0.35))
    ctx.addPath(shape); ctx.setFillColor(color(0x4F46E5)); ctx.fillPath()
    ctx.restoreGState()
}

// Background gradient (bottom-left → top-right).
ctx.saveGState()
ctx.addPath(shape); ctx.clip()
let grad = CGGradient(colorsSpace: cs, colors: brand as CFArray, locations: [0, 0.38, 0.72, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: rect.minX, y: rect.minY),
                       end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])

// Soft light bloom top-left for depth.
let bloom = CGGradient(colorsSpace: cs, colors: [color(0xFFFFFF, 0.35), color(0xFFFFFF, 0)] as CFArray,
                       locations: [0, 1])!
ctx.drawRadialGradient(bloom, startCenter: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.maxY - rect.height * 0.15),
                       startRadius: 0, endCenter: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.maxY - rect.height * 0.15),
                       endRadius: rect.width * 0.75, options: [])

// Three ascending bars (the "ranking").
let u = rect.width / 824            // scale unit
let base = rect.minY + 190 * u
let barW = 118 * u
let gap = 52 * u
let startX = rect.midX - (3 * barW + 2 * gap) / 2
let heights: [CGFloat] = [190, 300, 430].map { $0 * u }
for (i, h) in heights.enumerated() {
    let r = CGRect(x: startX + CGFloat(i) * (barW + gap), y: base, width: barW, height: h)
    let p = CGPath(roundedRect: r, cornerWidth: 30 * u, cornerHeight: 30 * u, transform: nil)
    ctx.addPath(p)
    ctx.setFillColor(color(0xFFFFFF, i == 2 ? 0.98 : 0.55 + 0.18 * CGFloat(i)))
    ctx.fillPath()
}

// Rising trend line over the bars with a glowing peak dot.
let pts = [CGPoint(x: startX - 26 * u, y: base + 250 * u),
           CGPoint(x: startX + barW + gap / 2, y: base + 330 * u),
           CGPoint(x: startX + 2 * (barW + gap) - gap / 2, y: base + 420 * u),
           CGPoint(x: startX + 3 * barW + 2 * gap - 14 * u, y: base + 525 * u)]
let line = CGMutablePath()
line.move(to: pts[0])
line.addCurve(to: pts[3], control1: CGPoint(x: pts[1].x, y: pts[1].y - 40 * u),
              control2: CGPoint(x: pts[2].x, y: pts[2].y - 30 * u))
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 24 * u, color: color(0x000000, 0.25))
ctx.addPath(line)
ctx.setStrokeColor(color(0xFFFFFF))
ctx.setLineWidth(30 * u)
ctx.setLineCap(.round)
ctx.strokePath()
ctx.restoreGState()

let peak = pts[3]
let glow = CGGradient(colorsSpace: cs, colors: [color(0xFFF7ED, 0.95), color(0xFFF7ED, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: peak, startRadius: 0, endCenter: peak, endRadius: 120 * u, options: [])
ctx.addEllipse(in: CGRect(x: peak.x - 38 * u, y: peak.y - 38 * u, width: 76 * u, height: 76 * u))
ctx.setFillColor(color(0xFFFFFF)); ctx.fillPath()
ctx.addEllipse(in: CGRect(x: peak.x - 17 * u, y: peak.y - 17 * u, width: 34 * u, height: 34 * u))
ctx.setFillColor(color(0xF97316)); ctx.fillPath()

// Subtle inner border.
ctx.restoreGState()
if !flat {
    ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerWidth: radius - 2, cornerHeight: radius - 2, transform: nil))
    ctx.setStrokeColor(color(0xFFFFFF, 0.18)); ctx.setLineWidth(4); ctx.strokePath()
}

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
