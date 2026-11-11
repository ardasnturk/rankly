// Renders the DMG window background (660×420 pt) at 1x and 2x.
// Usage: swift scripts/make-dmg-background.swift <outdir>
// Layout contract with scripts/build-dmg.sh: app icon centre (170, 215), Applications centre (490, 215).
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let W: CGFloat = 660, H: CGFloat = 420

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

for scale in [1, 2] {
    let s = CGFloat(scale)
    let ctx = CGContext(data: nil, width: Int(W * s), height: Int(H * s), bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s, y: s)
    // CoreGraphics origin is bottom-left; Finder coordinates are top-left. y(top) = H - y.

    // Deep background.
    let bg = CGGradient(colorsSpace: cs, colors: [color(0x14112B), color(0x0B0B14)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])

    // Brand blobs.
    func blob(_ x: CGFloat, _ yTop: CGFloat, _ r: CGFloat, _ hex: UInt32, _ a: CGFloat) {
        let g = CGGradient(colorsSpace: cs, colors: [color(hex, a), color(hex, 0)] as CFArray, locations: [0, 1])!
        let c = CGPoint(x: x, y: H - yTop)
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
    }
    blob(90, 60, 260, 0x4F46E5, 0.55)
    blob(330, 420, 280, 0x9333EA, 0.40)
    blob(600, 80, 240, 0xEC4899, 0.40)
    blob(640, 400, 200, 0xF97316, 0.30)

    // Title: "Rankly" with gradient fill.
    let title = NSAttributedString(string: "Rankly", attributes: [
        .font: NSFont.systemFont(ofSize: 34, weight: .heavy), .foregroundColor: NSColor.white])
    let line = CTLineCreateWithAttributedString(title)
    let tb = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    let tx = (W - tb.width) / 2, ty = H - 70
    ctx.saveGState()
    ctx.textPosition = CGPoint(x: tx, y: ty)
    ctx.setTextDrawingMode(.clip)
    CTLineDraw(line, ctx)
    let tg = CGGradient(colorsSpace: cs, colors: [color(0x818CF8), color(0xC084FC), color(0xF472B6), color(0xFB923C)] as CFArray,
                        locations: [0, 0.35, 0.7, 1])!
    ctx.drawLinearGradient(tg, start: CGPoint(x: tx, y: 0), end: CGPoint(x: tx + tb.width, y: 0), options: [])
    ctx.restoreGState()

    // Subtitle.
    let sub = NSAttributedString(string: "App Store keyword rank tracker", attributes: [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor(white: 1, alpha: 0.6)])
    let sl = CTLineCreateWithAttributedString(sub)
    let sb = CTLineGetBoundsWithOptions(sl, .useOpticalBounds)
    ctx.textPosition = CGPoint(x: (W - sb.width) / 2, y: H - 96)
    CTLineDraw(sl, ctx)

    // Glass pads behind the two icons.
    for cx in [CGFloat(170), 490] {
        let r = CGRect(x: cx - 72, y: H - 215 - 58, width: 144, height: 130)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 34, cornerHeight: 34, transform: nil))
        ctx.setFillColor(color(0xFFFFFF, 0.06)); ctx.fillPath()
        ctx.addPath(CGPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 34, cornerHeight: 34, transform: nil))
        ctx.setStrokeColor(color(0xFFFFFF, 0.12)); ctx.setLineWidth(1); ctx.strokePath()
    }

    // Light label pills: Finder draws icon labels in dark text on custom backgrounds.
    for cx in [CGFloat(170), 490] {
        let r = CGRect(x: cx - 62, y: H - 215 - 74 - 12, width: 124, height: 24)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 12, cornerHeight: 12, transform: nil))
        ctx.setFillColor(color(0xFFFFFF, 0.88)); ctx.fillPath()
    }

    // Arrow from app to Applications (gradient, dashed body + head).
    let y = H - 215
    ctx.saveGState()
    let arrow = CGMutablePath()
    arrow.move(to: CGPoint(x: 268, y: y))
    arrow.addLine(to: CGPoint(x: 378, y: y))
    ctx.addPath(arrow)
    ctx.setLineWidth(5); ctx.setLineCap(.round); ctx.setLineDash(phase: 0, lengths: [2, 11])
    ctx.replacePathWithStrokedPath(); ctx.clip()
    let ag = CGGradient(colorsSpace: cs, colors: [color(0x9333EA), color(0xEC4899), color(0xF97316)] as CFArray, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(ag, start: CGPoint(x: 268, y: 0), end: CGPoint(x: 392, y: 0), options: [])
    ctx.restoreGState()
    let head = CGMutablePath()
    head.move(to: CGPoint(x: 376, y: y + 13)); head.addLine(to: CGPoint(x: 394, y: y)); head.addLine(to: CGPoint(x: 376, y: y - 13))
    ctx.addPath(head); ctx.setStrokeColor(color(0xF97316)); ctx.setLineWidth(5); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.setLineDash(phase: 0, lengths: []); ctx.strokePath()

    // Footer hint.
    let hint = NSAttributedString(string: "Drag Rankly to Applications to install", attributes: [
        .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor(white: 1, alpha: 0.75)])
    let hl = CTLineCreateWithAttributedString(hint)
    let hb = CTLineGetBoundsWithOptions(hl, .useOpticalBounds)
    ctx.textPosition = CGPoint(x: (W - hb.width) / 2, y: 42)
    CTLineDraw(hl, ctx)

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    rep.size = NSSize(width: W, height: H)   // 72 dpi at 1x, 144 dpi at 2x
    let name = scale == 1 ? "dmg-background.png" : "dmg-background@2x.png"
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}
print("ok")
