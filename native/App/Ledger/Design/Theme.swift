import SwiftUI

/// The visual language: old money meets private fintech. Dark walnut, smoked glass, charcoal leather,
/// champagne gold, warm ivory, rose-gold accents. Change a colour here and it changes everywhere.
enum Theme {
    // Surfaces
    static let walnut = Color(red: 0.075, green: 0.060, blue: 0.050)        // app background
    static let walnutRaised = Color(red: 0.108, green: 0.088, blue: 0.074)
    static let leather = Color(red: 0.150, green: 0.132, blue: 0.120)       // charcoal leather
    static let glass = Color(red: 0.200, green: 0.170, blue: 0.145)         // smoked glass base (used with opacity)
    static let hairline = Color.white.opacity(0.08)

    // Text
    static let ivory = Color(red: 0.957, green: 0.925, blue: 0.867)
    static let ivoryMuted = Color(red: 0.745, green: 0.710, blue: 0.655)
    static let ivoryFaint = Color(red: 0.545, green: 0.515, blue: 0.470)

    // Accents
    static let gold = Color(red: 0.902, green: 0.812, blue: 0.604)          // champagne gold
    static let goldDeep = Color(red: 0.757, green: 0.639, blue: 0.376)
    static let roseGold = Color(red: 0.788, green: 0.604, blue: 0.545)

    // Meaning
    static let gain = Color(red: 0.498, green: 0.757, blue: 0.560)
    static let loss = Color(red: 0.863, green: 0.455, blue: 0.408)
    static let caution = Color(red: 0.890, green: 0.714, blue: 0.376)

    static let goldGradient = LinearGradient(colors: [gold, goldDeep], startPoint: .top, endPoint: .bottom)
    static let background = LinearGradient(colors: [Color(red: 0.105, green: 0.082, blue: 0.066), walnut], startPoint: .top, endPoint: .bottom)

    // Metrics
    enum Space { static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 32 }
    enum Radius { static let s: CGFloat = 10, m: CGFloat = 16, l: CGFloat = 22 }

    static func tone(_ name: String) -> Color {
        switch name { case "good": return gain; case "bad": return loss; case "warn": return caution; default: return ivoryMuted }
    }
    static func change(_ v: Double) -> Color { v > 0.0000001 ? gain : v < -0.0000001 ? loss : ivoryMuted }
}

/// Type styles. Figures use a serif face with tabular digits, labels a quiet small-caps-like sans.
extension Font {
    static func figure(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight, design: .serif).monospacedDigit() }
    static let heading = Font.system(.title3, design: .serif).weight(.semibold)
    static let label = Font.system(.caption, design: .default).weight(.medium)
    static let bodyText = Font.system(.subheadline, design: .default)
}
