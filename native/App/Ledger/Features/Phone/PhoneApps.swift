import SwiftUI
import Businesses
import Simulation

enum PhoneApp: String, CaseIterable, Hashable, Identifiable, Codable {
    case bank, stats, atlas
    case market, luxury
    case marketplace, auctions, airStay, techPro, store
    case competition, rankings, world
    case inbox, news, desk
    case profile, season, settings
    var id: String { rawValue }

    static var launcher: [PhoneApp] { PhoneSection.allCases.flatMap { $0.apps } }

    var title: String {
        switch self {
        case .bank: return "Bank"
        case .stats: return "Stats"
        case .atlas: return "Insurance"
        case .market: return "Market"
        case .luxury: return "Luxury"
        case .marketplace: return "Marketplace"
        case .airStay: return "AirStay"
        case .techPro: return "TechPro"
        case .store: return "Store"
        case .auctions: return "Auctions"
        case .competition: return "Competition"
        case .rankings: return "Rankings"
        case .world: return "World"
        case .inbox: return "Inbox"
        case .news: return "News"
        case .desk: return "Desk"
        case .profile: return "Profile"
        case .season: return "Season"
        case .settings: return "Settings"
        }
    }

    var glyph: String {
        switch self {
        case .bank: return Glyph.bank
        case .stats: return Glyph.stats
        case .atlas: return Glyph.atlas
        case .market: return Glyph.market
        case .luxury: return Glyph.luxury
        case .marketplace: return Glyph.marketplace
        case .airStay: return Glyph.airStay
        case .techPro: return Glyph.techPro
        case .store: return Glyph.shopBag
        case .auctions: return Glyph.auctionGavel
        case .competition: return Glyph.rivalsFlag
        case .rankings: return Glyph.rankPodium
        case .world: return Glyph.civicDome
        case .inbox: return Glyph.inbox
        case .news: return Glyph.news
        case .desk: return Glyph.deskNotebook
        case .profile: return Glyph.person
        case .season: return Glyph.achievements
        case .settings: return Glyph.settings
        }
    }

    var subtitle: String {
        switch self {
        case .bank: return "Cash, accounts, savings and loans"
        case .stats: return "Fun facts, reports and where the money went"
        case .atlas: return "Cover for your companies"
        case .market: return "Your markets, companies, investments and the exchange"
        case .luxury: return "Cars, watches, art, yachts, jets and homes"
        case .marketplace: return "Used items from private sellers"
        case .airStay: return "Offices, shops and storage to rent"
        case .techPro: return "Software, hardware, tools and vehicles"
        case .store: return "Gold, boxes and cosmetics"
        case .auctions: return "Bid on artifacts and cards, or sell your own"
        case .competition: return "Rivals, reviews and how you stand against the field"
        case .rankings: return "Leaderboards and the Hall of Fame"
        case .world: return "One president, one treasury, every country"
        case .inbox: return "Decisions, offers and warnings"
        case .news: return "The world, other players, government and weather"
        case .desk: return "One small question a day, and your notebook"
        case .profile: return "You, your trophies and your friends"
        case .season: return "Eight-week rewards, free and Plus"
        case .settings: return "How much you decide, saving, haptics"
        }
    }
}

enum PhoneSection: String, CaseIterable, Identifiable {
    case money = "Money"
    case market = "Market"
    case shops = "Shops"
    case field = "Competition and World"
    case daily = "Daily"
    case you = "You"
    var id: String { rawValue }

    var apps: [PhoneApp] {
        switch self {
        case .money: return [.bank, .stats, .atlas]
        case .market: return [.market, .luxury]
        case .shops: return [.marketplace, .auctions, .airStay, .techPro, .store]
        case .field: return [.competition, .rankings, .world]
        case .daily: return [.inbox, .news, .desk]
        case .you: return [.profile, .season, .settings]
        }
    }
}

extension Glyph {
    static let shopBag = "M5 8 H19 L18 20 H6 Z M9 8 V6 A3 3 0 0 1 15 6 V8 M9 12 V13 M15 12 V13"
    static let auctionGavel = "M10 4 L16 10 L13 13 L7 7 Z M11 12 L4 19 M13 20 H21"
    static let rankPodium = "M3 20 H21 M4 20 V13 H9 V20 M9 20 V7 H15 V20 M15 20 V15 H20 V20"
}

extension PhoneApp {
    var tint: Color {
        switch self {
        case .bank: return Color(hex: 0x86B4A0)
        case .stats: return Color(hex: 0x7F9CC0)
        case .atlas: return Color(hex: 0x7F9FC8)
        case .market: return Color(hex: 0x86B890)
        case .luxury: return Color(hex: 0xC48CB8)
        case .marketplace: return Color(hex: 0x4FA39B)
        case .airStay: return Color(hex: 0xCF6A6A)
        case .techPro: return Color(hex: 0x7FB088)
        case .store: return Color(hex: 0xE0BC5E)
        case .auctions: return Color(hex: 0xC9A66B)
        case .competition: return Color(hex: 0xB78F8A)
        case .rankings: return Color(hex: 0xD2B97C)
        case .world: return Color(hex: 0xCBAA6B)
        case .inbox: return Color(hex: 0xCF9A6A)
        case .news: return Color(hex: 0x7F9BC4)
        case .desk: return Color(hex: 0xB9A27A)
        case .profile: return Color(hex: 0xD6B889)
        case .season: return Color(hex: 0xD6B889)
        case .settings: return Color(hex: 0xA19B8F)
        }
    }
}

extension GateVisibility {
    var lockText: String? {
        if case .locked(let text) = self { return text }
        return nil
    }
}

extension PhoneApp {
    var gate: Gate? {
        switch self {
        case .inbox, .stats, .settings, .desk, .store, .profile, .market, .rankings, .competition, .auctions: return nil
        case .bank, .news, .season: return .bank
        case .marketplace: return .marketplace
        case .airStay: return .airstay
        case .techPro: return .techpro
        case .atlas: return .insurance
        case .luxury: return .luxury
        case .world: return nil
        }
    }

    func visibility(_ e: GameEngine) -> GateVisibility {
        if self == .desk { return e.deskOpen ? .open : .hidden }
        if self == .competition {
            if e.rivalsOpen { return .open }
            return Gates.visibility(.reviews, e.state, data: e.data)
        }
        if self == .auctions {
            if LevelGates.isOpen(.auctions, e.state) { return .open }
            let away: Int = LevelGates.level(.auctions) - PlayerLevel.info(e.state).level
            return away <= 1 ? .locked("Unlocks at level \(LevelGates.level(.auctions))") : .hidden
        }
        if self == .world {
            if LevelGates.isOpen(.government, e.state) { return .open }
            let away: Int = LevelGates.level(.government) - PlayerLevel.info(e.state).level
            return away <= 1 ? .locked("Unlocks at level \(LevelGates.level(.government))") : .hidden
        }
        guard let gate else { return .open }
        return Gates.visibility(gate, e.state, data: e.data)
    }
}
