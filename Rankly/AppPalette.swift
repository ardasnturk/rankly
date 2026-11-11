import SwiftUI
import AppKit

/// Colours extracted from a tracked app's icon; drives tint, bars, charts and header wash.
struct AppPalette: Equatable {
    var primary: Color
    var secondary: Color
    /// True when extracted from an icon (false = system accent fallback).
    var fromIcon: Bool

    static let system = AppPalette(primary: .accentColor, secondary: .accentColor, fromIcon: false)

    var gradient: LinearGradient {
        LinearGradient(colors: [primary, secondary], startPoint: .leading, endPoint: .trailing)
    }

    func wash(_ opacity: Double) -> LinearGradient {
        LinearGradient(colors: [primary.opacity(opacity), secondary.opacity(opacity * 0.6)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct AppPaletteKey: EnvironmentKey {
    static let defaultValue = AppPalette.system
}

extension EnvironmentValues {
    var appPalette: AppPalette {
        get { self[AppPaletteKey.self] }
        set { self[AppPaletteKey.self] = newValue }
    }
}

/// Downloads icons once and extracts their dominant vivid colours.
actor PaletteCache {
    static let shared = PaletteCache()
    private var cache: [String: AppPalette] = [:]

    func palette(for iconURL: String?) async -> AppPalette {
        guard let iconURL else { return .system }
        if let p = cache[iconURL] { return p }
        let p: AppPalette
        if iconURL.hasPrefix("demo:") {
            p = Self.demoPalette(iconURL)
        } else if let url = URL(string: iconURL),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data),
                  let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            p = Self.extract(cg) ?? .system
        } else {
            p = .system
        }
        cache[iconURL] = p
        return p
    }

    private static func demoPalette(_ spec: String) -> AppPalette {
        switch spec.split(separator: ":").last {
        case "green": return AppPalette(primary: .green, secondary: .mint, fromIcon: true)
        case "blue": return AppPalette(primary: .blue, secondary: .cyan, fromIcon: true)
        default: return AppPalette(primary: Color(hue: 0.07, saturation: 0.85, brightness: 0.95),
                                   secondary: Color(hue: 0.0, saturation: 0.75, brightness: 0.9), fromIcon: true)
        }
    }

    /// Hue histogram over a 40×40 downsample, weighted by saturation and brightness.
    static func extract(_ image: CGImage) -> AppPalette? {
        let n = 40
        var px = [UInt8](repeating: 0, count: n * n * 4)
        guard let ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))

        let buckets = 36
        var weight = [Double](repeating: 0, count: buckets)
        var sumH = [Double](repeating: 0, count: buckets)   // circular mean via x/y would be overkill at 10° buckets
        var sumS = [Double](repeating: 0, count: buckets)
        var sumB = [Double](repeating: 0, count: buckets)
        for i in stride(from: 0, to: px.count, by: 4) {
            let a = Double(px[i + 3]) / 255
            guard a > 0.5 else { continue }
            let c = NSColor(srgbRed: CGFloat(px[i]) / 255 / a, green: CGFloat(px[i + 1]) / 255 / a,
                            blue: CGFloat(px[i + 2]) / 255 / a, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
            c.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
            // Ignore white backgrounds, black outlines and greys.
            guard s > 0.28, b > 0.25 else { continue }
            let w = Double(s * s) * Double(b)
            let k = min(buckets - 1, Int(h * CGFloat(buckets)))
            weight[k] += w; sumH[k] += Double(h) * w; sumS[k] += Double(s) * w; sumB[k] += Double(b) * w
        }
        // Merge each bucket with its neighbours so a hue spread over two buckets still wins.
        let smoothed = (0..<buckets).map { k in
            weight[k] + 0.5 * weight[(k + 1) % buckets] + 0.5 * weight[(k + buckets - 1) % buckets]
        }
        guard let best = smoothed.indices.max(by: { smoothed[$0] < smoothed[$1] }), weight[best] > 0.5 else { return nil }

        func color(_ k: Int) -> Color {
            let w = weight[k]
            // Clamp for legibility as a tint in both light and dark mode.
            let s = min(0.95, max(0.5, sumS[k] / w))
            let b = min(0.88, max(0.55, sumB[k] / w))
            return Color(hue: sumH[k] / w, saturation: s, brightness: b)
        }
        // Secondary: strongest bucket at least 40° away, else a lighter shift of the primary hue.
        let far = smoothed.indices.filter { k in
            let d = abs(k - best); return min(d, buckets - d) >= 4 && weight[k] > weight[best] * 0.15
        }.max(by: { smoothed[$0] < smoothed[$1] })
        let primary = color(best)
        let secondary: Color = far.map(color) ?? {
            let w = weight[best]
            return Color(hue: (sumH[best] / w + 0.06).truncatingRemainder(dividingBy: 1),
                         saturation: min(0.9, max(0.45, sumS[best] / w * 0.85)),
                         brightness: min(0.92, max(0.6, sumB[best] / w * 1.05)))
        }()
        return AppPalette(primary: primary, secondary: secondary, fromIcon: true)
    }
}

/// Loads the palette for an icon and injects it (tint + environment) into a subtree.
struct AppPaletteModifier: ViewModifier {
    let iconURL: String?
    @State private var palette = AppPalette.system
    func body(content: Content) -> some View {
        content
            .environment(\.appPalette, palette)
            .tint(palette.fromIcon ? palette.primary : nil)
            .task(id: iconURL) {
                let p = await PaletteCache.shared.palette(for: iconURL)
                withAnimation(.easeInOut(duration: 0.35)) { palette = p }
            }
    }
}

extension View {
    func appPalette(from iconURL: String?) -> some View { modifier(AppPaletteModifier(iconURL: iconURL)) }
}

/// Popularity bar that uses the current app palette.
struct PopularityBar: View {
    @Environment(\.appPalette) private var palette
    let value: Int?
    var body: some View { ScoreBar(value: value, prefix: "~", tint: palette.gradient) }
}
