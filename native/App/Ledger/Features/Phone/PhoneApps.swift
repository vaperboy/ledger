import SwiftUI
import Businesses
import Simulation

enum PhoneApp: String, CaseIterable, Hashable, Identifiable, Codable {
    case bank, inbox, news, weather, luxury, ventures, reports, activity, market, reviews, settings
    case airStay, techPro, atlas
    case marketplace
    case season
    case friends
    case desk, rivals
    case country
    case store
    case profile
    var id: String { rawValue }

    static var launcher: [PhoneApp] { allCases.filter { $0 != .season && $0 != .profile } }

    var title: String {
        switch self {
        case .bank: return "Bank"
        case .inbox: return "Inbox"
        case .news: return "News"
        case .weather: return "Weather"
        case .luxury: return "Luxury"
        case .ventures: return "Ventures"
        case .reports: return "Reports"
        case .activity: return "Activity"
        case .market: return "Market"
        case .reviews: return "Reviews"
        case .settings: return "Settings"
        case .airStay: return "AirStay"
        case .techPro: return "TechPro Store"
        case .atlas: return "Atlas Insurance"
        case .marketplace: return "Marketplace"
        case .season: return "Season"
        case .friends: return "Friends"
        case .desk: return "Desk"
        case .rivals: return "Rivals"
        case .country: return "Country"
        case .store: return "Store"
        case .profile: return "Profile"
        }
    }

    var glyph: String {
        switch self {
        case .bank: return Glyph.bank
        case .inbox: return Glyph.inbox
        case .news: return Glyph.news
        case .weather: return Glyph.cloud
        case .luxury: return Glyph.luxury
        case .ventures: return Glyph.ventures
        case .reports: return Glyph.reports
        case .activity: return Glyph.list
        case .market: return Glyph.market
        case .reviews: return Glyph.reviewStar
        case .settings: return Glyph.settings
        case .airStay: return Glyph.airStay
        case .techPro: return Glyph.techPro
        case .atlas: return Glyph.atlas
        case .marketplace: return Glyph.marketplace
        case .season: return Glyph.achievements
        case .friends: return Glyph.team
        case .desk: return Glyph.deskNotebook
        case .rivals: return Glyph.rivalsFlag
        case .country: return Glyph.civicDome
        case .store: return Glyph.luxury
        case .profile: return Glyph.person
        }
    }

    var subtitle: String {
        switch self {
        case .bank: return "Accounts, savings and loans"
        case .inbox: return "Decisions, offers and warnings"
        case .news: return "Headlines and the business paper"
        case .weather: return "Conditions, forecast and warnings"
        case .luxury: return "Cars, watches, art, yachts, jets and homes"
        case .ventures: return "Startups, funds and stakes"
        case .reports: return "Weekly, monthly and yearly"
        case .activity: return "Why your money moved, in every account"
        case .market: return "Your markets, rivals, investments and the world"
        case .reviews: return "What customers say about you and your rivals"
        case .settings: return "How much you decide, saving, haptics"
        case .airStay: return "Offices, shops and storage to rent"
        case .techPro: return "Software, hardware, tools and vehicles"
        case .atlas: return "Cover for your companies"
        case .marketplace: return "Used items from private sellers"
        case .season: return "Eight-week rewards, free and Plus"
        case .friends: return "Players, requests and profiles"
        case .desk: return "One small question a day, and your notebook"
        case .rivals: return "Named competitors and what they are up to"
        case .country: return "Treasury, rates, president and the law"
        case .store: return "Gold, boxes and cosmetics"
        case .profile: return "You, your trophies and your friends"
        }
    }
}

extension PhoneApp {
    var tint: Color {
        switch self {
        case .bank: return Color(hex: 0x86B4A0)
        case .inbox: return Color(hex: 0xCF9A6A)
        case .news: return Color(hex: 0x7F9BC4)
        case .weather: return Color(hex: 0x93A9BD)
        case .luxury: return Color(hex: 0xC48CB8)
        case .ventures: return Color(hex: 0xE0BC5E)
        case .reports: return Color(hex: 0x7F9CC0)
        case .activity: return Color(hex: 0x8FA9B8)
        case .market: return Color(hex: 0x86B890)
        case .reviews: return Color(hex: 0xD2B97C)
        case .settings: return Color(hex: 0xA19B8F)
        case .airStay: return Color(hex: 0xCF6A6A)
        case .techPro: return Color(hex: 0x7FB088)
        case .atlas: return Color(hex: 0x7F9FC8)
        case .marketplace: return Color(hex: 0x4FA39B)
        case .season: return Color(hex: 0xD6B889)
        case .friends: return Color(hex: 0x8FB0C9)
        case .desk: return Color(hex: 0xB9A27A)
        case .rivals: return Color(hex: 0xB78F8A)
        case .country: return Color(hex: 0xCBAA6B)
        case .store: return Color(hex: 0xE0BC5E)
        case .profile: return Color(hex: 0xD6B889)
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
        case .inbox, .reports, .settings, .friends, .desk, .rivals, .store, .profile, .market: return nil
        case .bank: return .bank
        case .weather: return .weather
        case .marketplace: return .marketplace
        case .reviews: return .reviews
        case .airStay: return .airstay
        case .techPro: return .techpro
        case .atlas: return .insurance
        case .luxury: return .luxury
        case .ventures: return .venturesFeed
        case .activity, .news, .season: return .bank
        case .country: return nil
        }
    }

    func visibility(_ e: GameEngine) -> GateVisibility {
        if self == .desk { return e.deskOpen ? .open : .hidden }
        if self == .rivals { return e.rivalsOpen ? .open : .hidden }
        if self == .country {
            if LevelGates.isOpen(.government, e.state) { return .open }
            let away: Int = LevelGates.level(.government) - PlayerLevel.info(e.state).level
            return away <= 1 ? .locked("Unlocks at level \(LevelGates.level(.government))") : .hidden
        }
        guard let gate else { return .open }
        return Gates.visibility(gate, e.state, data: e.data)
    }
}
