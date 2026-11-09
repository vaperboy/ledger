import SwiftUI
import Simulation

/// What a piece of art is about: the category fixes the shape and pattern, the id fixes the symbol and colours.
enum ArtCategory: String, CaseIterable {
    case trade, artifact, theme, backdrop, namePlate, tradePlate, flair, box, badge, advisor, saveSlot, gold, avatar
}

/// The drawn emblem for every id the game has. Pure data: category -> shape and pattern, id -> symbol and colours, so a family looks alike.
enum EmblemCatalog {
    // MARK: Colour helpers

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

    // MARK: Trades

    private struct Family {
        var top: UInt32, bottom: UInt32, ink: UInt32
        var motif: EmblemMotif
    }

    private static let families: [String: Family] = [
        "svc": Family(top: 0x3E6A7A, bottom: 0x1E3A45, ink: 0xBFE3EC, motif: .dots),
        "venue": Family(top: 0xB5793E, bottom: 0x5E3A1A, ink: 0xFFE2B8, motif: .rays),
        "retail": Family(top: 0xA85A6E, bottom: 0x55283A, ink: 0xF7CDD8, motif: .stripes),
        "project": Family(top: 0xC2693A, bottom: 0x612E14, ink: 0xFFD6BC, motif: .grid),
        "prod": Family(top: 0x5E8A4E, bottom: 0x2B4423, ink: 0xD2EBC6, motif: .hills),
        "logi": Family(top: 0x4C6EA8, bottom: 0x1F3157, ink: 0xCADBF8, motif: .waves),
        "rent": Family(top: 0x7D62A8, bottom: 0x372850, ink: 0xDDD0F5, motif: .rings),
        "fin": Family(top: 0xC2A24A, bottom: 0x5A4612, ink: 0xFFF0BF, motif: .stars),
        "energy": Family(top: 0x9AAE3C, bottom: 0x4A5518, ink: 0xF1F7C0, motif: .rays),
        "hold": Family(top: 0x6E7480, bottom: 0x2D3036, ink: 0xE3E6EC, motif: .grid),
        "club": Family(top: 0xB04646, bottom: 0x551C1C, ink: 0xFFD0D0, motif: .stripes),
    ]

    /// Trade id -> (symbol, small second symbol, family). Every trade of `trades.json` has a row.
    private static let trades: [String: (String, String?, String)] = [
        "startup": ("lightbulb.fill", "arrow.up", "svc"), "cons": ("briefcase.fill", nil, "svc"), "tutor": ("graduationcap.fill", nil, "svc"),
        "carclean": ("car.fill", "drop.fill", "svc"), "photo": ("camera.fill", nil, "svc"), "handy": ("hammer.fill", nil, "svc"),
        "cleaning": ("bubbles.and.sparkles.fill", nil, "svc"), "webdev": ("chevron.left.forwardslash.chevron.right", nil, "svc"),
        "mktg": ("megaphone.fill", nil, "svc"), "law": ("scalemass.fill", nil, "svc"), "acctfirm": ("percent", nil, "svc"),
        "staffing": ("person.2.fill", nil, "svc"), "barber": ("scissors", nil, "svc"), "drivsk": ("steeringwheel", nil, "svc"),
        "physio": ("figure.walk", "cross.fill", "svc"), "estate": ("house.fill", "key.fill", "svc"), "travel": ("suitcase.fill", nil, "svc"),
        "insbroker": ("umbrella.fill", nil, "svc"), "finbroker": ("banknote.fill", nil, "svc"), "pets": ("pawprint.fill", nil, "svc"),
        "carrepair": ("wrench.and.screwdriver.fill", nil, "svc"), "dental": ("mouth.fill", nil, "svc"), "gamestudio": ("gamecontroller.fill", nil, "svc"),
        "security": ("lock.shield.fill", nil, "svc"),
        "foodtruck": ("box.truck.fill", "fork.knife", "venue"), "cafe": ("cup.and.saucer.fill", nil, "venue"), "restaurant": ("fork.knife", nil, "venue"),
        "nightclub": ("music.quarternote.3", "wineglass.fill", "venue"), "gym": ("dumbbell.fill", nil, "venue"), "hotel": ("bed.double.fill", nil, "venue"),
        "casino": ("suit.spade.fill", nil, "venue"), "fun": ("ticket.fill", nil, "venue"), "skires": ("snowflake", "mountain.2.fill", "venue"),
        "indoorski": ("figure.skiing.downhill", "building.fill", "venue"), "pcbang": ("display", "gamecontroller.fill", "venue"),
        "kiosk": ("storefront.fill", nil, "retail"), "boutique": ("tshirt.fill", nil, "retail"), "webshop": ("desktopcomputer", "cart.fill", "retail"),
        "grocery": ("cart.fill", nil, "retail"), "hardware": ("screwdriver.fill", nil, "retail"), "cardealer": ("car.side.fill", "tag.fill", "retail"),
        "usedcar": ("car.2.fill", "tag.fill", "retail"),
        "construction": ("building.2.fill", "hammer.fill", "project"), "electrician": ("bolt.fill", nil, "project"), "plumber": ("drop.fill", "wrench.fill", "project"),
        "realdev": ("house.and.flag.fill", nil, "project"), "event": ("party.popper.fill", nil, "project"), "engcons": ("ruler.fill", nil, "project"),
        "bakery": ("birthday.cake.fill", nil, "prod"), "brewery": ("mug.fill", nil, "prod"), "furniture": ("chair.lounge.fill", nil, "prod"),
        "salmon": ("fish.fill", nil, "prod"), "factory": ("gearshape.2.fill", nil, "prod"), "farm": ("leaf.fill", nil, "prod"), "vineyard": ("wineglass.fill", "leaf.fill", "prod"),
        "taxi": ("car.fill", "mappin", "logi"), "courier": ("bicycle", "shippingbox.fill", "logi"), "trucking": ("box.truck.fill", nil, "logi"),
        "shipping": ("ferry.fill", nil, "logi"), "airline": ("airplane", nil, "logi"), "wh3pl": ("shippingbox.fill", "arrow.left.arrow.right", "logi"),
        "carrental": ("key.fill", "car.fill", "logi"),
        "resrent": ("house.fill", "arrow.2.squarepath", "rent"), "comrent": ("building.fill", "arrow.2.squarepath", "rent"), "parking": ("parkingsign.circle.fill", nil, "rent"),
        "insco": ("checkmark.shield.fill", nil, "fin"), "bank": ("building.columns.fill", nil, "fin"), "fund": ("chart.line.uptrend.xyaxis", nil, "fin"),
        "power": ("sun.max.fill", "bolt.fill", "energy"), "oilgas": ("flame.fill", nil, "energy"),
        "hold": ("square.stack.3d.up.fill", nil, "hold"), "club": ("soccerball", nil, "club"),
    ]

    static func hasTrade(_ id: String) -> Bool { trades[id] != nil }

    static func trade(_ id: String) -> EmblemSpec? {
        guard let t = trades[id], let f = families[t.2] else { return nil }
        return EmblemSpec(symbol: t.0, badge: t.1, top: f.top, bottom: f.bottom, ink: f.ink, motif: f.motif, shape: .tile)
    }

    // MARK: Artifacts

    private static let collectionLook: [String: (top: UInt32, bottom: UInt32, ink: UInt32, motif: EmblemMotif)] = [
        "counting": (0xA8803A, 0x4A3512, 0xFFE9B0, .rings), "harbour": (0x2F7080, 0x143642, 0xBDEBF2, .waves),
        "market": (0xB2677A, 0x57293A, 0xFAD2DC, .stripes), "archive": (0x9C957F, 0x45423A, 0xF1ECDD, .grid),
    ]

    private static let artifactSymbols: [String: String] = [
        "abacus": "circle.grid.3x3.fill", "scales": "scalemass.fill", "strongbox": "archivebox.fill", "seal": "seal.fill",
        "rope": "lasso", "lantern": "flame.fill", "chart": "map.fill", "compass": "location.north.line.fill",
        "token": "centsign.circle.fill", "banner": "flag.2.crossed.fill", "bell": "bell.fill", "weights": "square.stack.3d.up.fill",
        "stamp": "checkmark.rectangle.fill", "map": "globe.europe.africa.fill", "scroll": "scroll.fill", "charter": "doc.richtext.fill",
    ]

    static func artifact(_ id: String) -> EmblemSpec? {
        guard let def = ArtifactCatalog.def(id), let look = collectionLook[def.collection] else { return nil }
        return EmblemSpec(symbol: artifactSymbols[id] ?? "seal.fill", top: look.top, bottom: look.bottom, ink: look.ink, motif: look.motif, shape: .medal)
    }

    // MARK: Cosmetics (colours come from the reward: tint first, deep tone second)

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

    // MARK: Boxes and pass rewards

    static func box(_ id: String) -> EmblemSpec {
        switch id {
        case "grand": return EmblemSpec(symbol: "shippingbox.fill", badge: "sparkles", top: 0xC2A24A, bottom: 0x4E3A10, ink: 0xFFF0BF, motif: .rays, shape: .tile)
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
