import SwiftUI

// The two looks of the online account screens. They are not part of the game's own Ivory Ledger: the welcome and profile screens are a
// passport desk in dusk plum and apricot, the Admin screen is a control room in graphite and signal amber.

extension OutsidePalette {
    /// Welcome and profile creation: plum-black ground, apricot accent, sage for what is granted.
    static let passport = OutsidePalette(
        ground: Color(hex: 0x15121A), ground2: Color(hex: 0x0E0C12), card: Color(hex: 0x201B28), cardDeep: Color(hex: 0x19151F),
        line: Color(hex: 0x332C3F), lineStrong: Color(hex: 0x4C4260), divider: Color(hex: 0x2B2536), hairline: Color(hex: 0x262030),
        ink: Color(hex: 0xF3ECE6), inkSoft: Color(hex: 0xC0B5BE), inkFaint: Color(hex: 0x9D93A3), inkDim: Color(hex: 0x82798A),
        accent: Color(hex: 0xEDA98A), accent2: Color(hex: 0xC9A7E0), onAccent: Color(hex: 0x1D120E),
        gain: Color(hex: 0x9CCFAE), loss: Color(hex: 0xE59A8F), caution: Color(hex: 0xE3BD7A))

    /// Admin: graphite with a blue cast, signal amber for the action, cold cyan for information.
    static let control = OutsidePalette(
        ground: Color(hex: 0x0A0E13), ground2: Color(hex: 0x06090C), card: Color(hex: 0x121921), cardDeep: Color(hex: 0x0E141B),
        line: Color(hex: 0x233040), lineStrong: Color(hex: 0x3B4D63), divider: Color(hex: 0x1D2835), hairline: Color(hex: 0x18222D),
        ink: Color(hex: 0xE6EDF4), inkSoft: Color(hex: 0xA9B7C6), inkFaint: Color(hex: 0x8797A8), inkDim: Color(hex: 0x6B7B8C),
        accent: Color(hex: 0xF2B84B), accent2: Color(hex: 0x5CC8D7), onAccent: Color(hex: 0x1A1204),
        gain: Color(hex: 0x7FD1A0), loss: Color(hex: 0xEC8E7C), caution: Color(hex: 0xF2B84B))
}

/// A round brass-like mark with the letter L: the welcome screen's seal. It draws once and does not move.
struct LedgerSeal: View {
    var size: CGFloat = 76
    @Environment(\.outsidePalette) private var P

    var body: some View {
        ZStack {
            Circle().strokeBorder(P.accent.opacity(0.9), lineWidth: 1.5)
            Circle().strokeBorder(P.accent.opacity(0.35), lineWidth: 0.8).padding(size * 0.09)
            Text("L").font(.system(size: size * 0.46, weight: .medium, design: .serif)).foregroundStyle(P.accent)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
