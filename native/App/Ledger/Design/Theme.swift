import SwiftUI

/// The visual language: Ivory Ledger. Editorial private banking on a flat charcoal page: hairline-separated sections instead
/// of cards, serif for the figures that matter, champagne small caps for labels and the one action. Change a token here and
/// it changes everywhere. See native/design/STYLE_IVORY_LEDGER.md.
enum Theme {
    // Surfaces: the Ivory Ledger page is one flat charcoal; structure comes from hairlines, not boxes.
    static let page = Color(red: 0.067, green: 0.075, blue: 0.082)           // #111315
    static let walnut = page
    static let walnutRaised = Color(red: 0.051, green: 0.059, blue: 0.067)    // #0D0F11 (tab bar, sheets)
    static let leather = walnutRaised
    static let glass = Color(red: 0.090, green: 0.098, blue: 0.106)
    static let pill = Color.white.opacity(0.06)
    static let pillOn = Color(red: 0.310, green: 0.247, blue: 0.192)
    static let hairline = Color(red: 0.937, green: 0.914, blue: 0.875).opacity(0.09)

    // Text
    static let ivory = Color(red: 0.937, green: 0.914, blue: 0.875)           // #EFE9DF
    static let ivoryMuted = Color(red: 0.616, green: 0.592, blue: 0.557)      // #9D978E
    static let ivoryFaint = Color(red: 0.424, green: 0.416, blue: 0.384)      // #6C6862
    static let cream = ivory

    // Champagne: labels, links and the one action
    static let gold = Color(red: 0.812, green: 0.694, blue: 0.522)            // #CFB185
    static let goldDeep = Color(red: 0.722, green: 0.600, blue: 0.427)
    static let goldLight = Color(red: 0.863, green: 0.753, blue: 0.592)
    static let roseGold = Color(red: 0.851, green: 0.682, blue: 0.384)
    static let slateBlue = Color(red: 0.322, green: 0.451, blue: 0.682)

    // Meaning
    static let gain = Color(red: 0.525, green: 0.780, blue: 0.616)            // #86C79D
    static let loss = Color(red: 0.863, green: 0.529, blue: 0.439)            // #DC8770
    static let caution = Color(red: 0.851, green: 0.682, blue: 0.384)         // #D9AE62

    static let goldGradient = LinearGradient(colors: [gold, gold], startPoint: .top, endPoint: .bottom)
    static let background = LinearGradient(colors: [page, page], startPoint: .top, endPoint: .bottom)

    // Metrics
    enum Space { static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 32; static let margin: CGFloat = 22 }
    enum Radius { static let s: CGFloat = 8, m: CGFloat = 10, l: CGFloat = 14 }

    static func tone(_ name: String) -> Color {
        switch name { case "good": return gain; case "bad": return loss; case "warn": return caution; default: return ivoryMuted }
    }
    static func change(_ v: Double) -> Color { v > 0.0000001 ? gain : v < -0.0000001 ? loss : ivoryMuted }
}

/// Type styles. Serif for the figures and titles that matter, a clean sans with tabular digits for the rest.
extension Font {
    static func figure(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight, design: .default).monospacedDigit() }
    /// The hero figure of a screen (net worth, group value, a company's profit).
    static func hero(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .serif).monospacedDigit() }
    static func serifTitle(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .serif) }
    static let heading = Font.system(.title3, design: .default).weight(.semibold)
    static let label = Font.system(.caption, design: .default).weight(.medium)
    static let bodyText = Font.system(.subheadline, design: .default)
    static let caps = Font.system(size: 10.5, weight: .semibold)
}

extension View {
    /// A section label: small caps, wide tracking, champagne.
    func capsLabel(_ tint: Color = Theme.gold) -> some View {
        self.font(.caps).tracking(1.6).textCase(.uppercase).foregroundStyle(tint)
    }
}

/// A 0.5 pt line.
struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
}
