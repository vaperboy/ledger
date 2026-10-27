import SwiftUI

/// The visual language: Ivory Ledger, new look approved 27 Oct 2026 (native/design/new-look-2026-10). Editorial private banking on
/// a charcoal page: bordered cards and outlined icon circles, serif titles and figures, champagne small caps for labels, and the
/// one filled button (Next Day). Colours and radii below are the mockups' exact values. Change a token here and it changes
/// everywhere. See native/design/STYLE_IVORY_LEDGER.md and Design/NewLook.swift for the shared pieces.
enum Theme {
    // Surfaces: the Ivory Ledger page is one flat charcoal; structure comes from hairlines, not boxes.
    static let page = Color(hex: 0x0F1011)                                    // #0F1011
    static let walnut = page
    static let walnutRaised = Color(hex: 0x141516)                            // #141516 (tab bar, sheets)
    static let leather = walnutRaised
    static let glass = Color(red: 0.090, green: 0.098, blue: 0.106)
    static let pill = Color.white.opacity(0.06)
    static let pillOn = Color(red: 0.310, green: 0.247, blue: 0.192)
    static let hairline = Color(red: 0.937, green: 0.914, blue: 0.875).opacity(0.09)

    // Text
    static let ivory = Color(hex: 0xF1EBDD)                                  // #F1EBDD
    static let ivoryMuted = Color(hex: 0xA19B8F)                             // #A19B8F
    static let ivoryFaint = Color(hex: 0x8A857C)                             // #8A857C
    static let ivoryDim = Color(hex: 0x75706A)                               // #75706A (footnotes, chevrons)
    static let cream = ivory

    // Champagne: labels, links and the one action
    static let gold = Color(hex: 0xD6B889)                                   // #D6B889
    static let goldDeep = Color(red: 0.722, green: 0.600, blue: 0.427)
    static let goldLight = Color(red: 0.863, green: 0.753, blue: 0.592)
    static let roseGold = Color(red: 0.851, green: 0.682, blue: 0.384)
    static let slateBlue = Color(red: 0.322, green: 0.451, blue: 0.682)

    // Meaning
    static let gain = Color(hex: 0x7FC79B)                                   // #7FC79B
    static let loss = Color(hex: 0xE58B78)                                   // #E58B78
    static let caution = Color(hex: 0xE0B064)                                // #E0B064
    /// The red notification bubble (counts on app icons and tabs). Not a loss colour: it only ever carries a number.
    static let alert = Color(hex: 0xE5584B)                                  // #E5584B

    // Cards and borders (new look)
    static let surface = Color(hex: 0x151617)                                // cards
    static let surfaceTable = Color(hex: 0x141516)                           // the sharp trade table, pickers, the tab bar
    static let border = Color(hex: 0x2B2C2E)                                 // card and table outline
    static let borderStrong = Color(hex: 0x3A3B3D)                           // round buttons, icon circles, small outline buttons
    static let divider = Color(hex: 0x242527)                                // line inside a card
    static let tableLine = Color(hex: 0x1E1F21)                              // line between table rows
    static let goldWash = Color(hex: 0xD6B889, opacity: 0.14)                // highlighted tab pill
    static let goldSelected = Color(hex: 0xD6B889, opacity: 0.16)            // selected segment / choice

    static let goldGradient = LinearGradient(colors: [gold, gold], startPoint: .top, endPoint: .bottom)
    static let background = LinearGradient(colors: [page, page], startPoint: .top, endPoint: .bottom)

    // Metrics
    enum Space { static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 32; static let margin: CGFloat = 22 }
    enum Radius {
        static let s: CGFloat = 8, m: CGFloat = 10, l: CGFloat = 14
        /// New look: big card (hero, accounts, phone banner) 16, standard card/tile 14, row card/quick action 12, sharp table/field 8,
        /// small outline button 12, app icon 15.
        static let hero: CGFloat = 16, card: CGFloat = 14, row: CGFloat = 12, table: CGFloat = 8, appIcon: CGFloat = 15
    }

    static func tone(_ name: String) -> Color {
        switch name { case "good": return gain; case "bad": return loss; case "warn": return caution; default: return ivoryMuted }
    }
    static func change(_ v: Double) -> Color { v > 0.0000001 ? gain : v < -0.0000001 ? loss : ivoryMuted }
}

extension Color {
    /// `Color(hex: 0xD6B889)`: the mockups' hex values, used by the Theme tokens.
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
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
    func capsLabel(_ tint: Color? = nil) -> some View {
        modifier(CapsLabelStyle(tint: tint))
    }
}

/// `capsLabel` as a modifier so the default colour follows the outside app's palette (champagne in the game's own screens).
struct CapsLabelStyle: ViewModifier {
    var tint: Color?
    @Environment(\.outsidePalette) private var palette
    func body(content: Content) -> some View {
        content.font(.caps).tracking(1.6).textCase(.uppercase).foregroundStyle(tint ?? palette.accent)
    }
}

/// A 0.5 pt line.
struct Hairline: View {
    @Environment(\.outsidePalette) private var palette
    var body: some View { Rectangle().fill(palette.hairline).frame(height: 0.5) }
}
