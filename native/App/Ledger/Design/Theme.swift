import SwiftUI

/// The visual language: old money meets private fintech. Values are sampled from the design concept: a cool charcoal
/// page, charcoal cards that fade darker downwards, cream and white text, one bronze accent, mint green for gains and an
/// orange red for losses. Change a colour here and it changes everywhere.
enum Theme {
    // Surfaces (concept: page #0a0e11–#15191c, cards #242526 fading to #131517)
    static let walnut = Color(red: 0.035, green: 0.047, blue: 0.057)        // app background
    static let walnutRaised = Color(red: 0.066, green: 0.078, blue: 0.090)
    static let leather = Color(red: 0.074, green: 0.082, blue: 0.090)       // card fill, bottom
    static let glass = Color(red: 0.143, green: 0.147, blue: 0.153)         // card fill, top
    static let pill = Color(red: 0.118, green: 0.133, blue: 0.145)          // unselected tab pill
    static let pillOn = Color(red: 0.310, green: 0.247, blue: 0.192)        // selected tab pill (bronze brown)
    static let hairline = Color.white.opacity(0.10)

    // Text (concept: figures #fefdf5, labels #cdcdcb, body #c4c7ca, the page title in cream #fcecd1)
    static let ivory = Color(red: 0.975, green: 0.968, blue: 0.945)
    static let ivoryMuted = Color(red: 0.775, green: 0.785, blue: 0.795)
    static let ivoryFaint = Color(red: 0.560, green: 0.575, blue: 0.590)
    static let cream = Color(red: 0.985, green: 0.925, blue: 0.810)

    // Accents: bronze (concept: lines #e2b984, button #f1caa3 → #c69b72)
    static let gold = Color(red: 0.890, green: 0.730, blue: 0.530)
    static let goldDeep = Color(red: 0.776, green: 0.608, blue: 0.447)
    static let goldLight = Color(red: 0.945, green: 0.792, blue: 0.639)
    static let roseGold = Color(red: 0.918, green: 0.659, blue: 0.420)       // orange bronze (demand ring)
    static let slateBlue = Color(red: 0.322, green: 0.451, blue: 0.682)      // charts

    // Meaning (concept: green #6ad495 / #74e29e, red #e88562 / #de503a)
    static let gain = Color(red: 0.420, green: 0.835, blue: 0.585)
    static let loss = Color(red: 0.900, green: 0.455, blue: 0.360)
    static let caution = Color(red: 0.918, green: 0.659, blue: 0.420)

    static let goldGradient = LinearGradient(colors: [goldLight, goldDeep], startPoint: .top, endPoint: .bottom)
    static let background = LinearGradient(colors: [Color(red: 0.082, green: 0.098, blue: 0.110), walnut, Color(red: 0.027, green: 0.037, blue: 0.045)], startPoint: .top, endPoint: .bottom)

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
