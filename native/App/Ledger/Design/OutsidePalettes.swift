import SwiftUI

/// The colours of one OUTSIDE phone app. Outside apps are "fake apps by other creators" (owner rule, 27 Oct 2026): each has its own
/// muted palette, used inside the app and on its launch splash. The icon on the Phone home keeps its muted tint (`PhoneApp.tint`).
/// A palette is defined once, here, and reaches the shared pieces (Card, CardSection, CardLine, GlyphView, IconCircle, FlatRow, NoteCard,
/// the round back button, `ledgerBackground`) through the `\.outsidePalette` environment, which `outsideScreen(_:)` sets. Everywhere
/// else the environment holds `.game`, which is exactly the Ivory Ledger `Theme` colours, so insider apps do not change.
struct OutsidePalette: Equatable {
    var ground: Color        // page
    var ground2: Color       // second stop of the splash gradient
    var card: Color
    var cardDeep: Color      // inset panels, pickers, tiles' picture wells
    var line: Color          // card and field outline
    var lineStrong: Color    // round buttons, icon circles, chips
    var divider: Color       // line inside a card
    var hairline: Color      // list separators
    var ink: Color           // main text
    var inkSoft: Color
    var inkFaint: Color
    var inkDim: Color        // chevrons, footnotes
    var accent: Color
    var accent2: Color       // a second accent where an app has one (otherwise equal to `accent`)
    var onAccent: Color      // text on a filled accent badge
    var gain: Color
    var loss: Color
    var caution: Color
    var isLight: Bool = false

    var accentWash: Color { accent.opacity(0.14) }
    var accentSelected: Color { accent.opacity(0.16) }
    var accent2Wash: Color { accent2.opacity(0.14) }

    func change(_ v: Double) -> Color { v > 0.0000001 ? gain : v < -0.0000001 ? loss : inkSoft }

    /// The game's own colours: what every insider screen uses.
    static let game = OutsidePalette(
        ground: Theme.page, ground2: Color(hex: 0x0B0C0D), card: Theme.surface, cardDeep: Theme.surfaceTable,
        line: Theme.border, lineStrong: Theme.borderStrong, divider: Theme.divider, hairline: Theme.hairline,
        ink: Theme.ivory, inkSoft: Theme.ivoryMuted, inkFaint: Theme.ivoryFaint, inkDim: Theme.ivoryDim,
        accent: Theme.gold, accent2: Theme.gold, onAccent: Theme.page, gain: Theme.gain, loss: Theme.loss, caution: Theme.caution)

    /// News: newsprint. Warm off-white page, ink-black text, a muted red rule. Light on purpose (it imitates a paper).
    static let news = OutsidePalette(
        ground: Color(hex: 0xF1EBDC), ground2: Color(hex: 0xE6DEC9), card: Color(hex: 0xF8F4E8), cardDeep: Color(hex: 0xE8DFCA),
        line: Color(hex: 0xCDC2A8), lineStrong: Color(hex: 0x8C826C), divider: Color(hex: 0xD6CCB4), hairline: Color(hex: 0xD6CCB4),
        ink: Color(hex: 0x1C1A17), inkSoft: Color(hex: 0x433E35), inkFaint: Color(hex: 0x645D4E), inkDim: Color(hex: 0x6F6858),
        accent: Color(hex: 0x9A3B32), accent2: Color(hex: 0x9A3B32), onAccent: Color(hex: 0xF8F4E8),
        gain: Color(hex: 0x2F6B45), loss: Color(hex: 0x9A3B32), caution: Color(hex: 0x86601E), isLight: true)

    /// Luxury: near-black with antique brass.
    static let luxury = OutsidePalette(
        ground: Color(hex: 0x0A0907), ground2: Color(hex: 0x16120B), card: Color(hex: 0x14110D), cardDeep: Color(hex: 0x0F0D0A),
        line: Color(hex: 0x2E2819), lineStrong: Color(hex: 0x4F4328), divider: Color(hex: 0x28231A), hairline: Color(hex: 0x221D12),
        ink: Color(hex: 0xEFE6D2), inkSoft: Color(hex: 0xB8AC90), inkFaint: Color(hex: 0x998E76), inkDim: Color(hex: 0x7F7560),
        accent: Color(hex: 0xB8964F), accent2: Color(hex: 0xB8964F), onAccent: Color(hex: 0x0A0907),
        gain: Color(hex: 0x8FB58A), loss: Color(hex: 0xD08A72), caution: Color(hex: 0xC9A24F))

    /// Ventures: a startup feed in muted teal and violet on dark.
    static let ventures = OutsidePalette(
        ground: Color(hex: 0x12111C), ground2: Color(hex: 0x0D1517), card: Color(hex: 0x1B1A29), cardDeep: Color(hex: 0x16151F),
        line: Color(hex: 0x2E2D42), lineStrong: Color(hex: 0x45445F), divider: Color(hex: 0x2A293C), hairline: Color(hex: 0x252438),
        ink: Color(hex: 0xECEAF4), inkSoft: Color(hex: 0xB2B0C6), inkFaint: Color(hex: 0x9391AB), inkDim: Color(hex: 0x797791),
        accent: Color(hex: 0x6FB5AB), accent2: Color(hex: 0xA397D6), onAccent: Color(hex: 0x0D1517),
        gain: Color(hex: 0x7FC7A4), loss: Color(hex: 0xE0907F), caution: Color(hex: 0xD2B46E))

    /// World: deep teal and sea-green, like a chart.
    static let world = OutsidePalette(
        ground: Color(hex: 0x0C2326), ground2: Color(hex: 0x081A1D), card: Color(hex: 0x12302F), cardDeep: Color(hex: 0x0F2A2C),
        line: Color(hex: 0x225049), lineStrong: Color(hex: 0x37746C), divider: Color(hex: 0x1D4543), hairline: Color(hex: 0x1A3E3E),
        ink: Color(hex: 0xE8F3F0), inkSoft: Color(hex: 0xABCAC4), inkFaint: Color(hex: 0x88ADA7), inkDim: Color(hex: 0x70938E),
        accent: Color(hex: 0x72B89F), accent2: Color(hex: 0x8DC4CD), onAccent: Color(hex: 0x08191B),
        gain: Color(hex: 0x8FD1A8), loss: Color(hex: 0xE39A86), caution: Color(hex: 0xD2BC80))

    /// Rich list: dark navy, muted platinum, gold for the podium.
    static let richList = OutsidePalette(
        ground: Color(hex: 0x0D1526), ground2: Color(hex: 0x090F1C), card: Color(hex: 0x141E35), cardDeep: Color(hex: 0x101830),
        line: Color(hex: 0x273555), lineStrong: Color(hex: 0x3E4E74), divider: Color(hex: 0x222F4C), hairline: Color(hex: 0x1D2845),
        ink: Color(hex: 0xEEF0F5), inkSoft: Color(hex: 0xB4BBCD), inkFaint: Color(hex: 0x959DB3), inkDim: Color(hex: 0x7B839C),
        accent: Color(hex: 0xC4CAD6), accent2: Color(hex: 0xC9A862), onAccent: Color(hex: 0x0D1526),
        gain: Color(hex: 0x86C4A0), loss: Color(hex: 0xDE9484), caution: Color(hex: 0xC9A862))

    /// Weather: blues. Deep dusk-blue ground, pale-blue cards, white text; the accent follows the condition
    /// (`kind` is a `WeatherEvents` kind: sun, mixed, rain, snow, heat, cold, storm).
    static func weather(kind: String) -> OutsidePalette {
        var p = OutsidePalette(
            ground: Color(hex: 0x16304D), ground2: Color(hex: 0x0E1D31), card: Color(hex: 0x24405E), cardDeep: Color(hex: 0x1B3552),
            line: Color(hex: 0x3A5878), lineStrong: Color(hex: 0x5B7B9F), divider: Color(hex: 0x33506F), hairline: Color(hex: 0x2B4663),
            ink: Color(hex: 0xF4F8FC), inkSoft: Color(hex: 0xBFD0E3), inkFaint: Color(hex: 0x9BB1C9), inkDim: Color(hex: 0x849CB7),
            accent: Color(hex: 0xA9BCD0), accent2: Color(hex: 0xA9BCD0), onAccent: Color(hex: 0x0E1D31),
            gain: Color(hex: 0x8FCFAE), loss: Color(hex: 0xE89E8D), caution: Color(hex: 0xE3C27E))
        switch kind {
        case "sun": p.accent = Color(hex: 0xE3C27E)                                         // clear: warm
        case "heat": p.accent = Color(hex: 0xE0A670)
        case "rain": p.accent = Color(hex: 0x7FA3C7); p.ground = Color(hex: 0x182A40)       // steel blue
        case "snow": p.accent = Color(hex: 0xD3E3F0)
        case "cold": p.accent = Color(hex: 0x9CC3DA)
        case "storm": p.accent = Color(hex: 0xA99DCB); p.ground = Color(hex: 0x1A2038); p.ground2 = Color(hex: 0x101426) // slate violet
        default: break
        }
        p.accent2 = p.accent
        return p
    }
}

private struct OutsidePaletteKey: EnvironmentKey { static let defaultValue: OutsidePalette = .game }
extension EnvironmentValues {
    /// The palette of the outside app being drawn; `.game` (the Ivory Ledger colours) everywhere else.
    var outsidePalette: OutsidePalette {
        get { self[OutsidePaletteKey.self] }
        set { self[OutsidePaletteKey.self] = newValue }
    }
}

extension PhoneApp {
    /// The app's own palette when it is an outside app; nil for the player's own (insider) apps.
    var outsidePalette: OutsidePalette? {
        switch self {
        case .weather: return .weather(kind: "sun")
        case .news: return .news
        case .luxury: return .luxury
        case .ventures: return .ventures
        case .world: return .world
        case .richList: return .richList
        case .bank, .inbox, .stats, .goals, .reports, .achievements, .settings: return nil
        }
    }
}
