import SwiftUI

struct OutsidePalette: Equatable {
    var ground: Color
    var ground2: Color
    var card: Color
    var cardDeep: Color
    var line: Color
    var lineStrong: Color
    var divider: Color
    var hairline: Color
    var ink: Color
    var inkSoft: Color
    var inkFaint: Color
    var inkDim: Color
    var accent: Color
    var accent2: Color
    var onAccent: Color
    var gain: Color
    var loss: Color
    var caution: Color
    var isLight: Bool = false
    var raised: Color? = nil

    var page: Color { ground }
    var surface: Color { card }
    var surfaceRaised: Color { raised ?? card }
    var inset: Color { ink.opacity(0.05) }
    var accentInk: Color { onAccent }
    var warn: Color { caution }
    var alert: Color { Theme.alert }
    var focus: Color { accent }
    var scrim: Color { Color.black.opacity(isLight ? 0.35 : 0.55) }

    var accentWash: Color { accent.opacity(0.14) }
    var accentSelected: Color { accent.opacity(0.14) }
    var accent2Wash: Color { accent2.opacity(0.14) }

    func change(_ v: Double) -> Color { v > 0.0000001 ? gain : v < -0.0000001 ? loss : inkSoft }

    static let game = OutsidePalette(
        ground: Theme.page, ground2: Color(hex: 0x0B0C0D), card: Theme.surface, cardDeep: Theme.surface,
        line: Theme.line, lineStrong: Theme.lineStrong, divider: Theme.line, hairline: Theme.line,
        ink: Theme.ink, inkSoft: Theme.inkSoft, inkFaint: Theme.inkFaint, inkDim: Theme.inkFaint,
        accent: Theme.accent, accent2: Theme.accent, onAccent: Theme.accentInk, gain: Theme.gain, loss: Theme.loss, caution: Theme.warn,
        raised: Theme.surfaceRaised)

    static let news = OutsidePalette(
        ground: Color(hex: 0xF1EBDC), ground2: Color(hex: 0xE6DEC9), card: Color(hex: 0xF8F4E8), cardDeep: Color(hex: 0xE8DFCA),
        line: Color(hex: 0xCDC2A8), lineStrong: Color(hex: 0x8C826C), divider: Color(hex: 0xD6CCB4), hairline: Color(hex: 0xD6CCB4),
        ink: Color(hex: 0x1C1A17), inkSoft: Color(hex: 0x433E35), inkFaint: Color(hex: 0x645D4E), inkDim: Color(hex: 0x6F6858),
        accent: Color(hex: 0x9A3B32), accent2: Color(hex: 0x9A3B32), onAccent: Color(hex: 0xF8F4E8),
        gain: Color(hex: 0x2F6B45), loss: Color(hex: 0x9A3B32), caution: Color(hex: 0x86601E), isLight: true)

    static let luxury = OutsidePalette(
        ground: Color(hex: 0x0A0B0E), ground2: Color(hex: 0x12141A), card: Color(hex: 0x171A22), cardDeep: Color(hex: 0x101218),
        line: Color(hex: 0x262932), lineStrong: Color(hex: 0x4A4128), divider: Color(hex: 0x22252D), hairline: Color(hex: 0x1C1F26),
        ink: Color(hex: 0xECE8DC), inkSoft: Color(hex: 0xB4B0A4), inkFaint: Color(hex: 0x95928A), inkDim: Color(hex: 0x76746E),
        accent: Color(hex: 0xC5A059), accent2: Color(hex: 0xE6C775), onAccent: Color(hex: 0x0A0B0E),
        gain: Color(hex: 0x6FBF9C), loss: Color(hex: 0xD48A94), caution: Color(hex: 0xC9A24F))

    static let forest = OutsidePalette(
        ground: Color(hex: 0x0D1F1A), ground2: Color(hex: 0x08140F), card: Color(hex: 0x132A22), cardDeep: Color(hex: 0x0F221B),
        line: Color(hex: 0x24433A), lineStrong: Color(hex: 0x3E5F52), divider: Color(hex: 0x1F3B31), hairline: Color(hex: 0x1A332A),
        ink: Color(hex: 0xF0EADA), inkSoft: Color(hex: 0xBAC2B4), inkFaint: Color(hex: 0x96A397), inkDim: Color(hex: 0x7C8A7F),
        accent: Color(hex: 0xD1B27A), accent2: Color(hex: 0xE3C98F), onAccent: Color(hex: 0x0D1F1A),
        gain: Color(hex: 0x86CFA0), loss: Color(hex: 0xE5907D), caution: Color(hex: 0xE0B46A))

    static let accounting = OutsidePalette(
        ground: Color(hex: 0xF2EDE0), ground2: Color(hex: 0xE9E2D0), card: Color(hex: 0xFBF8EF), cardDeep: Color(hex: 0xEDE6D3),
        line: Color(hex: 0xDDD4BD), lineStrong: Color(hex: 0xB9AD8F), divider: Color(hex: 0xE4DCC8), hairline: Color(hex: 0xE4DCC8),
        ink: Color(hex: 0x16241F), inkSoft: Color(hex: 0x44524B), inkFaint: Color(hex: 0x65706A), inkDim: Color(hex: 0x8A9189),
        accent: Color(hex: 0x1F4A3A), accent2: Color(hex: 0xA9812F), onAccent: Color(hex: 0xF7F2E4),
        gain: Color(hex: 0x2B7A4B), loss: Color(hex: 0xAE3F2B), caution: Color(hex: 0x8F6410), isLight: true)

    static let bank = accounting

    static let inbox = OutsidePalette(
        ground: Color(hex: 0x0F1618), ground2: Color(hex: 0x0A1012), card: Color(hex: 0x1A2528), cardDeep: Color(hex: 0x141D20),
        line: Color(hex: 0x26343A), lineStrong: Color(hex: 0x3A4D55), divider: Color(hex: 0x202D32), hairline: Color(hex: 0x1B282C),
        ink: Color(hex: 0xE8EEEF), inkSoft: Color(hex: 0xAEBDC1), inkFaint: Color(hex: 0x8DA0A6), inkDim: Color(hex: 0x738489),
        accent: Color(hex: 0x7DB89A), accent2: Color(hex: 0x7FA6C4), onAccent: Color(hex: 0x0A1214),
        gain: Color(hex: 0x84C7A3), loss: Color(hex: 0xE59A88), caution: Color(hex: 0xDDB872))

    static let airStay = OutsidePalette(
        ground: Color(hex: 0xF7F4F1), ground2: Color(hex: 0xEDE7E2), card: Color(hex: 0xFFFFFF), cardDeep: Color(hex: 0xF1ECE8),
        line: Color(hex: 0xE3DCD6), lineStrong: Color(hex: 0xB9AEA6), divider: Color(hex: 0xEBE5E0), hairline: Color(hex: 0xEBE5E0),
        ink: Color(hex: 0x241F1E), inkSoft: Color(hex: 0x56504C), inkFaint: Color(hex: 0x6D6661), inkDim: Color(hex: 0x8B837D),
        accent: Color(hex: 0xD2384A), accent2: Color(hex: 0xA82A3A), onAccent: Color(hex: 0xFFFFFF),
        gain: Color(hex: 0x2B7A4B), loss: Color(hex: 0xB3261E), caution: Color(hex: 0x8F6410), isLight: true)

    static let techPro = OutsidePalette(
        ground: Color(hex: 0xF2F6F3), ground2: Color(hex: 0xE5ECE7), card: Color(hex: 0xFFFFFF), cardDeep: Color(hex: 0xE9F0EB),
        line: Color(hex: 0xD8E2DB), lineStrong: Color(hex: 0xA3B5A9), divider: Color(hex: 0xE1E9E3), hairline: Color(hex: 0xE1E9E3),
        ink: Color(hex: 0x16241C), inkSoft: Color(hex: 0x42524A), inkFaint: Color(hex: 0x5C6B63), inkDim: Color(hex: 0x82908A),
        accent: Color(hex: 0x1E6B45), accent2: Color(hex: 0xC9811F), onAccent: Color(hex: 0xFFFFFF),
        gain: Color(hex: 0x2B7A4B), loss: Color(hex: 0xB3261E), caution: Color(hex: 0x8F6410), isLight: true)

    static let atlas = OutsidePalette(
        ground: Color(hex: 0xF1F4F9), ground2: Color(hex: 0xE3E9F2), card: Color(hex: 0xFFFFFF), cardDeep: Color(hex: 0xE8EEF7),
        line: Color(hex: 0xD6DEEA), lineStrong: Color(hex: 0xA2B0C4), divider: Color(hex: 0xE0E6F0), hairline: Color(hex: 0xE0E6F0),
        ink: Color(hex: 0x15213A), inkSoft: Color(hex: 0x40506B), inkFaint: Color(hex: 0x586783), inkDim: Color(hex: 0x7F8CA3),
        accent: Color(hex: 0x1F4B8F), accent2: Color(hex: 0x2F78C8), onAccent: Color(hex: 0xFFFFFF),
        gain: Color(hex: 0x2B7A4B), loss: Color(hex: 0xB3261E), caution: Color(hex: 0x8F6410), isLight: true)

    static let marketplace = OutsidePalette(
        ground: Color(hex: 0xF6F2EA), ground2: Color(hex: 0xEBE4D6), card: Color(hex: 0xFFFDF8), cardDeep: Color(hex: 0xEEE8DA),
        line: Color(hex: 0xE0D8C6), lineStrong: Color(hex: 0xB4AA92), divider: Color(hex: 0xE8E1D1), hairline: Color(hex: 0xE8E1D1),
        ink: Color(hex: 0x14282A), inkSoft: Color(hex: 0x41544F), inkFaint: Color(hex: 0x5D6C66), inkDim: Color(hex: 0x86908A),
        accent: Color(hex: 0x0E7C7B), accent2: Color(hex: 0xC47A2C), onAccent: Color(hex: 0xFFFFFF),
        gain: Color(hex: 0x2B7A4B), loss: Color(hex: 0xB3261E), caution: Color(hex: 0x8F6410), isLight: true)
    static let marketplaceSplash = OutsidePalette(
        ground: Color(hex: 0x0E5F5E), ground2: Color(hex: 0x0A2E32), card: Color(hex: 0x187370), cardDeep: Color(hex: 0x0B4A4B),
        line: Color(hex: 0x4FA39B), lineStrong: Color(hex: 0x8FCBC3), divider: Color(hex: 0x4FA39B), hairline: Color(hex: 0x4FA39B),
        ink: Color(hex: 0xFFFFFF), inkSoft: Color(hex: 0xDDF1ED), inkFaint: Color(hex: 0xBFE0DA), inkDim: Color(hex: 0xA0CFC8),
        accent: Color(hex: 0xFFFFFF), accent2: Color(hex: 0xFFFFFF), onAccent: Color(hex: 0x0E5F5E),
        gain: Color(hex: 0xFFFFFF), loss: Color(hex: 0xFFFFFF), caution: Color(hex: 0xFFFFFF))

    static let airStaySplash = OutsidePalette(
        ground: Color(hex: 0xD2384A), ground2: Color(hex: 0x8E1F2D), card: Color(hex: 0xDD5262), cardDeep: Color(hex: 0xB62D3D),
        line: Color(hex: 0xE88A95), lineStrong: Color(hex: 0xF3B8BF), divider: Color(hex: 0xE88A95), hairline: Color(hex: 0xE88A95),
        ink: Color(hex: 0xFFFFFF), inkSoft: Color(hex: 0xFBE3E6), inkFaint: Color(hex: 0xF6CDD2), inkDim: Color(hex: 0xF0B5BC),
        accent: Color(hex: 0xFFFFFF), accent2: Color(hex: 0xFFFFFF), onAccent: Color(hex: 0xD2384A),
        gain: Color(hex: 0xFFFFFF), loss: Color(hex: 0xFFFFFF), caution: Color(hex: 0xFFFFFF))
    static let techProSplash = OutsidePalette(
        ground: Color(hex: 0x1E6B45), ground2: Color(hex: 0x0F3D27), card: Color(hex: 0x2A7D55), cardDeep: Color(hex: 0x175738),
        line: Color(hex: 0x5BA27F), lineStrong: Color(hex: 0x9CCDB3), divider: Color(hex: 0x5BA27F), hairline: Color(hex: 0x5BA27F),
        ink: Color(hex: 0xFFFFFF), inkSoft: Color(hex: 0xE0F0E7), inkFaint: Color(hex: 0xC4DFD0), inkDim: Color(hex: 0xA6CDB8),
        accent: Color(hex: 0xFFFFFF), accent2: Color(hex: 0xFFFFFF), onAccent: Color(hex: 0x1E6B45),
        gain: Color(hex: 0xFFFFFF), loss: Color(hex: 0xFFFFFF), caution: Color(hex: 0xFFFFFF))
    static let atlasSplash = OutsidePalette(
        ground: Color(hex: 0x1F4B8F), ground2: Color(hex: 0x0F2850), card: Color(hex: 0x2D5CA3), cardDeep: Color(hex: 0x193F78),
        line: Color(hex: 0x6C93CC), lineStrong: Color(hex: 0xA4BFE6), divider: Color(hex: 0x6C93CC), hairline: Color(hex: 0x6C93CC),
        ink: Color(hex: 0xFFFFFF), inkSoft: Color(hex: 0xE0EAF8), inkFaint: Color(hex: 0xC4D5EE), inkDim: Color(hex: 0xA6BDDF),
        accent: Color(hex: 0xFFFFFF), accent2: Color(hex: 0xFFFFFF), onAccent: Color(hex: 0x1F4B8F),
        gain: Color(hex: 0xFFFFFF), loss: Color(hex: 0xFFFFFF), caution: Color(hex: 0xFFFFFF))
}

private struct OutsidePaletteKey: EnvironmentKey { static let defaultValue: OutsidePalette = .game }
extension EnvironmentValues {
    var outsidePalette: OutsidePalette {
        get { self[OutsidePaletteKey.self] }
        set { self[OutsidePaletteKey.self] = newValue }
    }
}

extension PhoneApp {
    var outsidePalette: OutsidePalette? { outsidePalette(ownBankIsMain: false) }

    func outsidePalette(ownBankIsMain: Bool) -> OutsidePalette? {
        switch self {
        case .news: return .news
        case .luxury: return .luxury
        case .bank: return ownBankIsMain ? nil : .forest
        case .inbox: return .inbox
        case .stats, .market, .settings, .season, .desk, .store, .profile, .competition, .rankings: return nil
        case .airStay: return .airStay
        case .techPro: return .techPro
        case .atlas: return .atlas
        case .marketplace: return .marketplace
        case .world: return .civic
        }
    }

    func splashPalette(ownBankIsMain: Bool) -> OutsidePalette? {
        switch self {
        case .airStay: return .airStaySplash
        case .techPro: return .techProSplash
        case .atlas: return .atlasSplash
        case .marketplace: return .marketplaceSplash
        default: return outsidePalette(ownBankIsMain: ownBankIsMain)
        }
    }
}
