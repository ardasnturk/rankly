// Renders the menu bar template icon (black on transparent; macOS tints it).
// Usage: swift scripts/make-menubar-icon.swift <outdir>
import AppKit
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
for scale in [1, 2, 3] {
    let s = CGFloat(18 * scale)
    let ctx = CGContext(data: nil, width: Int(s), height: Int(s), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let u = s / 18
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    // three ascending bars
    for (i, h) in [5.0, 8.0, 11.5].enumerated() {
        let r = CGRect(x: (2.0 + Double(i) * 4.9) * u, y: 1.5 * u, width: 3.4 * u, height: CGFloat(h) * u)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 1 * u, cornerHeight: 1 * u, transform: nil)); ctx.fillPath()
    }
    // rising line + peak dot
    ctx.setStrokeColor(CGColor(gray: 0, alpha: 1)); ctx.setLineWidth(1.6 * u); ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: 1.2 * u, y: 10.2 * u))
    ctx.addCurve(to: CGPoint(x: 15.2 * u, y: 15.6 * u), control1: CGPoint(x: 6 * u, y: 11.5 * u), control2: CGPoint(x: 11 * u, y: 13 * u))
    ctx.strokePath()
    ctx.fillEllipse(in: CGRect(x: 13.6 * u, y: 14 * u, width: 3.4 * u, height: 3.4 * u))
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    let name = scale == 1 ? "menubar.png" : "menubar@\(scale)x.png"
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}
print("ok")
