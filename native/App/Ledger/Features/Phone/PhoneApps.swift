import SwiftUI
import Businesses
import Simulation

/// The apps on the Phone home screen. Inbox is an app here, not a tab; everything that used to sit in the More sheet is an app too.
/// Add a screen to the Phone by adding a case, its icon (`Glyph`) and its destination in `PhoneAppScreen`.
enum PhoneApp: String, CaseIterable, Hashable, Identifiable, Codable {
    case bank, accounting, inbox, news, weather, stats, goals, luxury, ventures, reports, market, reviews, achievements, settings
    /// The three shopping and insurance apps (each in its own colours): places to rent, equipment and software, insurance.
    case airStay, techPro, atlas
    /// The second-hand market: every used item for sale, from private sellers, one price talk at a time.
    case marketplace
    /// The Season Pass: eight real weeks of rewards, a free and a Ledger Plus track.
    case season
    var id: String { rawValue }

    /// The apps with a tile on the Phone home. Goals and Reports are pages of Stats, and Ventures is in the Projects tab: their cases stay as routes only.
    static var launcher: [PhoneApp] { allCases.filter { $0 != .goals && $0 != .reports && $0 != .ventures } }

    var title: String {
        switch self {
        case .bank: return "Bank"
        case .accounting: return "Accounting"
        case .inbox: return "Inbox"
        case .news: return "News"
        case .weather: return "Weather"
        case .stats: return "Stats"
        case .goals: return "Goals"
        case .luxury: return "Luxury"
        case .ventures: return "Ventures"
        case .reports: return "Reports"
        case .market: return "Market"
        case .reviews: return "Reviews"
        case .achievements: return "Achievements"
        case .settings: return "Settings"
        case .airStay: return "AirStay"
        case .techPro: return "TechPro Store"
        case .atlas: return "Atlas Insurance"
        case .marketplace: return "Marketplace"
        case .season: return "Season"
        }
    }

    /// The app icon drawn on the Phone grid.
    var glyph: String {
        switch self {
        case .bank: return Glyph.bank
        case .accounting: return Glyph.accounting
        case .inbox: return Glyph.inbox
        case .news: return Glyph.news
        case .weather: return Glyph.cloud
        case .stats: return Glyph.stats
        case .goals: return Glyph.goals
        case .luxury: return Glyph.luxury
        case .ventures: return Glyph.ventures
        case .reports: return Glyph.reports
        case .market: return Glyph.market
        case .reviews: return Glyph.reviewStar
        case .achievements: return Glyph.achievements
        case .settings: return Glyph.settings
        case .airStay: return Glyph.airStay
        case .techPro: return Glyph.techPro
        case .atlas: return Glyph.atlas
        case .marketplace: return Glyph.marketplace
        case .season: return Glyph.achievements
        }
    }

    /// The grey line under the app's title.
    var subtitle: String {
        switch self {
        case .bank: return "Accounts, savings and loans"
        case .accounting: return "Books, payroll, invoices and records"
        case .inbox: return "Decisions, offers and warnings"
        case .news: return "Headlines and the business paper"
        case .weather: return "Conditions, forecast and warnings"
        case .stats: return "Your record, goals, reports and where money went"
        case .goals: return "What to aim for next"
        case .luxury: return "Cars, watches, art, yachts, jets and homes"
        case .ventures: return "Startups, funds and stakes"
        case .reports: return "Weekly, monthly and yearly"
        case .market: return "Your markets, rivals, investments and the world"
        case .reviews: return "What customers say about you and your rivals"
        case .achievements: return "Trophies and awards"
        case .settings: return "How much you decide, saving, haptics"
        case .airStay: return "Offices, shops and storage to rent"
        case .techPro: return "Software, hardware, tools and vehicles"
        case .atlas: return "Cover for your companies"
        case .marketplace: return "Used items from private sellers"
        case .season: return "Eight-week rewards, free and Plus"
        }
    }
}

extension PhoneApp {
    /// The muted colour inside the app's icon (Ivory Ledger tints, never loud). The glyph and the label always stay, so colour is never alone.
    var tint: Color {
        switch self {
        case .bank: return Color(hex: 0x86B4A0)
        case .accounting: return Color(hex: 0xA8B88A)
        case .inbox: return Color(hex: 0xCF9A6A)
        case .news: return Color(hex: 0x7F9BC4)
        case .weather: return Color(hex: 0x93A9BD)
        case .stats: return Color(hex: 0x9A94C4)
        case .goals: return Color(hex: 0xC8706A)
        case .luxury: return Color(hex: 0xC48CB8)
        case .ventures: return Color(hex: 0xE0BC5E)
        case .reports: return Color(hex: 0x7F9CC0)
        case .market: return Color(hex: 0x86B890)
        case .reviews: return Color(hex: 0xD2B97C)
        case .achievements: return Color(hex: 0xE0A458)
        case .settings: return Color(hex: 0xA19B8F)
        case .airStay: return Color(hex: 0xCF6A6A)
        case .techPro: return Color(hex: 0x7FB088)
        case .atlas: return Color(hex: 0x7F9FC8)
        case .marketplace: return Color(hex: 0x4FA39B)
        case .season: return Color(hex: 0xD6B889)
        }
    }
}

/// A page of an app that has several (Stats with Activity, Goals and Reports; Goals and Achievements). The existing screens are reused unchanged; the app is
/// a table with one row per page, each opening that page.
enum PhonePage: String, Hashable, Identifiable {
    case stats = "Stats", activity = "Activity"
    case goals = "Goals", reports = "Reports", achievements = "Achievements"
    var id: String { rawValue }

    var glyph: String {
        switch self {
        case .stats: return Glyph.stats
        case .activity: return Glyph.list
        case .goals: return Glyph.goals
        case .reports: return Glyph.reports
        case .achievements: return Glyph.achievements
        }
    }

    var note: String {
        switch self {
        case .stats: return "Your figures and how they moved"
        case .activity: return "Why your money moved, in every account"
        case .goals: return "What you are working towards"
        case .reports: return "Weekly, monthly and yearly"
        case .achievements: return "Trophies and awards"
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
        case .inbox, .reports, .settings: return nil
        case .bank: return .bank
        case .accounting: return .accounting
        case .weather: return .weather
        case .marketplace: return .marketplace
        case .reviews: return .reviews
        case .airStay: return .airstay
        case .techPro: return .techpro
        case .atlas: return .insurance
        case .luxury: return .luxury
        case .ventures: return .venturesFeed
        case .stats, .goals, .news, .market, .achievements, .season: return .bank
        }
    }

    /// Open, dimmed with its lock text, or not on the Phone yet. A game started without the ladder has everything open.
    func visibility(_ e: GameEngine) -> GateVisibility {
        guard let gate else { return .open }
        return Gates.visibility(gate, e.state, data: e.data)
    }
}
