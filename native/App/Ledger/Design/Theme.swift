import SwiftUI

/// The visual language: old money meets private fintech. Near-black, smoked glass cards, bronze accent,
/// warm ivory text, green and red only for gains and losses. Change a colour here and it changes everywhere.
enum Theme {
    // Surfaces: near-black with a warm cast, cards a step lighter
    static let walnut = Color(red: 0.047, green: 0.042, blue: 0.038)        // app background
    static let walnutRaised = Color(red: 0.075, green: 0.068, blue: 0.062)
    static let leather = Color(red: 0.105, green: 0.097, blue: 0.090)       // card fill
    static let glass = Color(red: 0.150, green: 0.135, blue: 0.120)         // lighter card fill (used with opacity)
    static let hairline = Color.white.opacity(0.09)

    // Text
    static let ivory = Color(red: 0.965, green: 0.945, blue: 0.910)
    static let ivoryMuted = Color(red: 0.735, green: 0.705, blue: 0.665)
    static let ivoryFaint = Color(red: 0.535, green: 0.510, blue: 0.480)

    // Accents: bronze, the one warm highlight
    static let gold = Color(red: 0.835, green: 0.690, blue: 0.520)
    static let goldDeep = Color(red: 0.640, green: 0.490, blue: 0.345)
    static let roseGold = Color(red: 0.790, green: 0.620, blue: 0.560)

    // Meaning
    static let gain = Color(red: 0.325, green: 0.780, blue: 0.545)
    static let loss = Color(red: 0.890, green: 0.385, blue: 0.360)
    static let caution = Color(red: 0.930, green: 0.730, blue: 0.360)

    static let goldGradient = LinearGradient(colors: [gold, goldDeep], startPoint: .top, endPoint: .bottom)
    static let background = LinearGradient(colors: [Color(red: 0.085, green: 0.066, blue: 0.050), walnut, walnut], startPoint: .top, endPoint: .bottom)

    // Metrics
    enum Space { static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 32 }
    enum Radius { static let s: CGFloat = 10, m: CGFloat = 14, l: CGFloat = 20 }

    static func tone(_ name: String) -> Color {
        switch name { case "good": return gain; case "bad": return loss; case "warn": return caution; default: return ivoryMuted }
    }
    static func change(_ v: Double) -> Color { v > 0.0000001 ? gain : v < -0.0000001 ? loss : ivoryMuted }
}

/// Type styles. Figures and text share one clean sans with tabular digits; labels are small and quiet.
extension Font {
    static func figure(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight, design: .default).monospacedDigit() }
    static let heading = Font.system(.title3, design: .default).weight(.semibold)
    static let label = Font.system(.caption, design: .default).weight(.medium)
    static let bodyText = Font.system(.subheadline, design: .default)
}
