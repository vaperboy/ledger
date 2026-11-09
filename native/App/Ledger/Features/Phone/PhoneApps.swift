import SwiftUI
import Businesses
import Simulation

/// The apps on the Phone home screen. Inbox is an app here, not a tab; everything that used to sit in the More sheet is an app too.
/// Add a screen to the Phone by adding a case, its icon (`Glyph`) and its destination in `PhoneAppScreen`.
enum PhoneApp: String, CaseIterable, Hashable, Identifiable, Codable {
    case bank, inbox, news, weather, stats, luxury, ventures, reports, activity, market, reviews, achievements, settings
    /// The three shopping and insurance apps (each in its own colours): places to rent, equipment and software, insurance.
    case airStay, techPro, atlas
    /// The second-hand market: every used item for sale, from private sellers, one price talk at a time.
    case marketplace
    /// The Season Pass: eight real weeks of rewards, a free and a Ledger Plus track.
    case season
    /// Friends and profiles: the online side. Open without a game or an account (a guest is shown how to link one).
    case friends
    /// Calm daily and slow-moving pages that open a few weeks in: the Desk (one question a day) and Rivals (named competitors).
    case desk, rivals
    /// The state: treasury, rates, president, printed money, elections, convictions and the dark side of business.
    case country
    /// Gold, boxes, cosmetics and the way to the Cabinet and auctions. Shown only to players who confirmed they are 18 or older.
    case store
    var id: String { rawValue }

    /// The apps with a tile on the Phone home. Ventures is in the Projects tab: its case stays as a route only.
    static var launcher: [PhoneApp] { allCases.filter { $0 != .ventures } }

    var title: String {
        switch self {
        case .bank: return "Bank"
        case .inbox: return "Inbox"
        case .news: return "News"
        case .weather: return "Weather"
        case .stats: return "Stats"
        case .luxury: return "Luxury"
        case .ventures: return "Ventures"
        case .reports: return "Reports"
        case .activity: return "Activity"
        case .market: return "Market"
        case .reviews: return "Reviews"
        case .achievements: return "Achievements"
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
        }
    }

    /// The app icon drawn on the Phone grid.
    var glyph: String {
        switch self {
        case .bank: return Glyph.bank
        case .inbox: return Glyph.inbox
        case .news: return Glyph.news
        case .weather: return Glyph.cloud
        case .stats: return Glyph.stats
        case .luxury: return Glyph.luxury
        case .ventures: return Glyph.ventures
        case .reports: return Glyph.reports
        case .activity: return Glyph.list
        case .market: return Glyph.market
        case .reviews: return Glyph.reviewStar
        case .achievements: return Glyph.achievements
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
        }
    }

    /// The grey line under the app's title.
    var subtitle: String {
        switch self {
        case .bank: return "Accounts, savings and loans"
        case .inbox: return "Decisions, offers and warnings"
        case .news: return "Headlines and the business paper"
        case .weather: return "Conditions, forecast and warnings"
        case .stats: return "How things are going"
        case .luxury: return "Cars, watches, art, yachts, jets and homes"
        case .ventures: return "Startups, funds and stakes"
        case .reports: return "Weekly, monthly and yearly"
        case .activity: return "Why your money moved, in every account"
        case .market: return "Your markets, rivals, investments and the world"
        case .reviews: return "What customers say about you and your rivals"
        case .achievements: return "Your trophies and awards"
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
        case .store: return "Gold, boxes, cosmetics and auctions"
        }
    }
}

extension PhoneApp {
    /// The muted colour inside the app's icon (Ivory Ledger tints, never loud). The glyph and the label always stay, so colour is never alone.
    var tint: Color {
        switch self {
        case .bank: return Color(hex: 0x86B4A0)
        case .inbox: return Color(hex: 0xCF9A6A)
        case .news: return Color(hex: 0x7F9BC4)
        case .weather: return Color(hex: 0x93A9BD)
        case .stats: return Color(hex: 0x9A94C4)
        case .luxury: return Color(hex: 0xC48CB8)
        case .ventures: return Color(hex: 0xE0BC5E)
        case .reports: return Color(hex: 0x7F9CC0)
        case .activity: return Color(hex: 0x8FA9B8)
        case .market: return Color(hex: 0x86B890)
        case .reviews: return Color(hex: 0xD2B97C)
        case .achievements: return Color(hex: 0xE0A458)
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
        }
    }
}

extension GateVisibility {
    /// The `Unlocks ...` line of a locked-and-near gate; nil otherwise.
    var lockText: String? {
        if case .locked(let text) = self { return text }
        return nil
    }
}

extension PhoneApp {
    /// The gate that holds the app back. Inbox, Reports and Settings are always open. The apps the table names have their
    /// own gate; the rest (Stats, News, Achievements, Market and the like) wait for the bank gate, the end of the first-session ladder.
    var gate: Gate? {
        switch self {
        case .inbox, .reports, .settings, .friends, .desk, .rivals, .store: return nil   // the Desk and Rivals have their own unlock (`visibility`)
        case .bank: return .bank
        case .weather: return .weather
        case .marketplace: return .marketplace
        case .reviews: return .reviews
        case .airStay: return .airstay
        case .techPro: return .techpro
        case .atlas: return .insurance
        case .luxury: return .luxury
        case .ventures: return .venturesFeed
        case .stats, .activity, .news, .market, .achievements, .season, .country: return .bank
        }
    }

    /// Open, dimmed with its lock text, or not on the Phone yet. A game started without the ladder has everything open.
    func visibility(_ e: GameEngine) -> GateVisibility {
        if self == .desk { return e.deskOpen ? .open : .hidden }
        if self == .rivals { return e.rivalsOpen ? .open : .hidden }
        guard let gate else { return .open }
        return Gates.visibility(gate, e.state, data: e.data)
    }
}
