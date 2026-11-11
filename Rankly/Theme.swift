import SwiftUI

/// Brand palette: indigo → purple → pink → orange (same as the app icon and the website).
enum Theme {
    static let indigo = Color(red: 0x4F / 255, green: 0x46 / 255, blue: 0xE5 / 255)
    static let purple = Color(red: 0x93 / 255, green: 0x33 / 255, blue: 0xEA / 255)
    static let pink   = Color(red: 0xEC / 255, green: 0x48 / 255, blue: 0x99 / 255)
    static let orange = Color(red: 0xF9 / 255, green: 0x73 / 255, blue: 0x16 / 255)

    static let colors = [indigo, purple, pink, orange]
    static let gradient = LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    static let diagonal = LinearGradient(colors: colors, startPoint: .bottomLeading, endPoint: .topTrailing)
    static let cool = LinearGradient(colors: [indigo, purple], startPoint: .leading, endPoint: .trailing)
    static let warm = LinearGradient(colors: [pink, orange], startPoint: .leading, endPoint: .trailing)

    /// Very soft wash used behind headers.
    static func wash(_ opacity: Double = 0.14) -> some View {
        LinearGradient(colors: colors.map { $0.opacity(opacity) }, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Prominent button with the brand gradient.
struct GradientButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Capsule().fill(Theme.gradient))
            .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
            .shadow(color: Theme.purple.opacity(configuration.isPressed ? 0.1 : 0.35), radius: 8, y: 3)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GradientButtonStyle {
    static var gradient: GradientButtonStyle { GradientButtonStyle() }
}

/// Rounded card surface.
struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.background.secondary))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.07)))
    }
}

/// The app mark drawn in SwiftUI (sidebar, menu bar header, about).
struct RanklyMark: View {
    var size: CGFloat = 28
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(Theme.diagonal)
            HStack(alignment: .bottom, spacing: size * 0.07) {
                ForEach(0..<3) { i in
                    RoundedRectangle(cornerRadius: size * 0.04)
                        .fill(.white.opacity(0.55 + 0.2 * Double(i)))
                        .frame(width: size * 0.15, height: size * [0.22, 0.36, 0.52][i])
                }
            }
            .offset(y: size * 0.08)
        }
        .frame(width: size, height: size)
    }
}

/// "Rankly" wordmark with gradient fill.
struct Wordmark: View {
    var font: Font = .title3.weight(.heavy)
    var body: some View {
        Text("Rankly").font(font).foregroundStyle(Theme.gradient)
    }
}
