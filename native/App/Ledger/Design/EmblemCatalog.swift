import SwiftUI
import GameCore
import Simulation

enum ArtCategory: String, CaseIterable {
    case trade, artifact, theme, backdrop, namePlate, tradePlate, flair, box, badge, advisor, saveSlot, gold, avatar
}

enum AppContent {
    static func load(_ kind: String, _ name: String) -> JSONValue {
        guard let root = Bundle.main.resourcePath,
              let raw = FileManager.default.contents(atPath: root + "/Content/" + kind + "/" + name + ".json"),
              let json = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return .null }
        return json
    }
}

extension EmblemMotif {
    init(named s: String) {
        switch s {
        case "rays": self = .rays
        case "rings": self = .rings
        case "dots": self = .dots
        case "stripes": self = .stripes
        case "waves": self = .waves
        case "grid": self = .grid
        case "hills": self = .hills
        case "stars": self = .stars
        case "plateLines": self = .plateLines
        default: self = .none
        }
    }
}

enum EmblemCatalog {

    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func ch(_ v: UInt32, _ shift: UInt32) -> Double { Double((v >> shift) & 0xFF) }
        func blend(_ shift: UInt32) -> UInt32 {
            let v: Double = ch(a, shift) * (1 - t) + ch(b, shift) * t
            return UInt32(max(0, min(255, v.rounded()))) << shift
        }
        return blend(16) | blend(8) | blend(0)
    }

    static func hash(_ s: String) -> Int { Int(truncatingIfNeeded: ArtLibrary.stableHash(s) & 0x7FFF_FFFF) }

    static func spec(category: ArtCategory, id: String, colors: [UInt32]) -> EmblemSpec? {
        switch category {
        case .trade: return trade(id)
        case .artifact: return artifact(id)
        case .theme: return theme(id, colors)
        case .backdrop: return backdrop(id, colors)
        case .namePlate: return plate(id, colors, symbol: "textformat")
        case .tradePlate: return plate(id, colors, symbol: "storefront.fill")
        case .flair: return flair(id, colors)
        case .box: return box(id)
        case .badge: return badge(id, colors)
        case .advisor: return EmblemSpec(symbol: "quote.bubble.fill", top: 0x4A4F63, bottom: 0x23263A, ink: 0xD7DBF2, motif: .dots, shape: .tile)
        case .saveSlot: return EmblemSpec(symbol: "externaldrive.fill", badge: "plus", top: 0x55606B, bottom: 0x262C33, ink: 0xDCE4EC, motif: .grid, shape: .tile)
        case .gold: return EmblemSpec(symbol: "dollarsign.circle.fill", top: 0xE0BC5E, bottom: 0x7A5A1C, ink: 0xFFF4CF, motif: .rings, shape: .round)
        case .avatar: return AvatarCatalog.def(id)?.spec
        }
    }

    private struct Family {
        var top: UInt32, bottom: UInt32, ink: UInt32
        var motif: EmblemMotif
    }

    private static let tradeFile: JSONValue = AppContent.load("trade_icons", "trade_icons")

    private static let families: [String: Family] = {
        var out: [String: Family] = [:]
        for (k, v) in tradeFile["families"].object {
            out[k] = Family(top: ContentFile.color(v["top"]), bottom: ContentFile.color(v["bottom"]), ink: ContentFile.color(v["ink"]), motif: EmblemMotif(named: v["motif"].string))
        }
        return out
    }()

    private static let trades: [String: (String, String?, String)] = {
        var out: [String: (String, String?, String)] = [:]
        for e in tradeFile["trades"].array {
            out[e["id"].string] = (e["symbol"].string, e["badge"].isNull ? nil : e["badge"].string, e["family"].string)
        }
        return out
    }()

    static let neutral: EmblemSpec = EmblemSpec(symbol: "photo", top: 0x55606B, bottom: 0x262C33, ink: 0xDCE4EC, motif: .none, shape: .tile)

    static func hasTrade(_ id: String) -> Bool { trades[id] != nil }

    static func trade(_ id: String) -> EmblemSpec? {
        guard let t = trades[id], let f = families[t.2] else { return nil }
        return EmblemSpec(symbol: t.0, badge: t.1, top: f.top, bottom: f.bottom, ink: f.ink, motif: f.motif, shape: .tile)
    }

    static func card(_ d: CardDef) -> EmblemSpec {
        EmblemSpec(symbol: d.logo.isEmpty ? "rectangle.on.rectangle.fill" : d.logo, badge: d.isAnimated ? "sparkles" : nil, top: d.colors[0], bottom: d.colors[d.colors.count - 1],
                   ink: mix(d.colors[0], 0xFFFFFF, 0.65), motif: d.isAnimated ? .stars : (d.kind == .company ? .rings : .dots), shape: .tile)
    }

    static func artifact(_ id: String) -> EmblemSpec? {
        if let c = CardCatalog.def(id) { return card(c) }
        guard let def = ArtifactCatalog.def(id), let col = ArtifactCatalog.collection(def.collection) else { return nil }
        return EmblemSpec(symbol: def.symbol.isEmpty ? "seal.fill" : def.symbol, top: col.look.top, bottom: col.look.bottom, ink: col.look.ink,
                          motif: EmblemMotif(named: col.look.motif), shape: .medal)
    }

    private static func pair(_ colors: [UInt32]) -> (tint: UInt32, deep: UInt32) {
        let tint: UInt32 = colors.first ?? 0xD6B889
        let deep: UInt32 = colors.count > 1 ? colors[1] : mix(tint, 0x000000, 0.7)
        return (tint, deep)
    }

    static func theme(_ id: String, _ colors: [UInt32]) -> EmblemSpec {
        let p = pair(colors)
        return EmblemSpec(symbol: "paintpalette.fill", top: mix(p.deep, p.tint, 0.3), bottom: p.deep, ink: p.tint, motif: .rings, shape: .round)
    }

    private static let backdropSymbols: [(String, String)] = [
        ("fog", "cloud.fog.fill"), ("plum", "moon.fill"), ("aurora", "sparkles"), ("slate", "cloud.fill"), ("sand", "sun.max.fill"),
        ("dawn", "sunrise.fill"), ("harbour", "water.waves"),
    ]

    static func backdrop(_ id: String, _ colors: [UInt32]) -> EmblemSpec {
        let p = pair(colors)
        let sym: String = backdropSymbols.first { id.contains($0.0) }?.1 ?? "mountain.2.fill"
        return EmblemSpec(symbol: sym, top: mix(p.tint, 0x000000, 0.1), bottom: p.deep, ink: mix(p.tint, 0xFFFFFF, 0.45), motif: .hills, shape: .plate, placement: .corner)
    }

    static func plate(_ id: String, _ colors: [UInt32], symbol: String) -> EmblemSpec {
        let p = pair(colors)
        return EmblemSpec(symbol: symbol, top: mix(p.deep, p.tint, 0.22), bottom: p.deep, ink: p.tint, motif: .plateLines, shape: .plate, placement: .leading)
    }

    static func flair(_ id: String, _ colors: [UInt32]) -> EmblemSpec {
        let p = pair(colors)
        var symbol: String = "star.fill"
        var badge: String? = nil
        var motif: EmblemMotif = .rings
        if id.contains("laurel") { symbol = "leaf.fill"; badge = "star.fill" }
        else if id.contains("sun") { symbol = "sun.max.fill"; motif = .rays }
        else if id.contains("pin") { symbol = "pin.fill" }
        else if id.contains("crest") { symbol = "shield.lefthalf.filled"; badge = "star.fill" }
        else if id.contains("archive") { symbol = "seal.fill" }
        return EmblemSpec(symbol: symbol, badge: badge, top: mix(p.deep, p.tint, 0.4), bottom: p.deep, ink: mix(p.tint, 0xFFFFFF, 0.2), motif: motif, shape: .medal)
    }

    static func box(_ id: String) -> EmblemSpec {
        switch id {
        case "grand": return EmblemSpec(symbol: "shippingbox.fill", badge: "sparkles", top: 0xC2A24A, bottom: 0x4E3A10, ink: 0xFFF0BF, motif: .rays, shape: .tile)
        case "cardElite": return EmblemSpec(symbol: "rectangle.on.rectangle.fill", badge: "sparkles", top: 0xC2A24A, bottom: 0x4E3A10, ink: 0xFFF0BF, motif: .stars, shape: .tile)
        case "cardPremium": return EmblemSpec(symbol: "rectangle.on.rectangle.fill", top: 0x8C6FD6, bottom: 0x2A1E4F, ink: 0xE4DAFA, motif: .rings, shape: .tile)
        case "cardBasic": return EmblemSpec(symbol: "rectangle.on.rectangle.fill", top: 0x4C7C96, bottom: 0x1B3040, ink: 0xD2E6F2, motif: .dots, shape: .tile)
        case "cabinet": return EmblemSpec(symbol: "shippingbox.fill", top: 0x4C6EA8, bottom: 0x1B2C4F, ink: 0xD2E0FA, motif: .grid, shape: .tile)
        default: return EmblemSpec(symbol: "gift.fill", top: 0x4F8A80, bottom: 0x1E403B, ink: 0xCFF0E8, motif: .dots, shape: .tile)
        }
    }

    static func badge(_ id: String, _ colors: [UInt32]) -> EmblemSpec {
        var top: UInt32 = 0xC9B08A
        var bottom: UInt32 = 0x4A3F2C
        if id.contains("bronze") { top = 0xC68A55; bottom = 0x5A3418 }
        else if id.contains("silver") { top = 0xC3C9D3; bottom = 0x4B515C }
        else if id.contains("gold") || id.contains("crown") { top = 0xE6C463; bottom = 0x6B4E12 }
        else if id.contains("plus") { top = 0x8F7AC4; bottom = 0x2F2550 }
        let premium: Bool = id.contains("crown") || id.contains("plus")
        return EmblemSpec(symbol: "rosette", badge: premium ? "star.fill" : nil, top: top, bottom: bottom, ink: 0xFFF6E0, motif: .stars, shape: .medal)
    }
}

extension EmblemFrame {
    init(_ rarity: BoxRarity?) {
        switch rarity {
        case .none: self = .plain
        case .some(.common): self = .common
        case .some(.rare): self = .rare
        case .some(.epic): self = .epic
        case .some(.legendary): self = .legendary
        }
    }
}
