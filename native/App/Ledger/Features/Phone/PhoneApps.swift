import SwiftUI

/// The apps on the Phone home screen. Inbox is an app here, not a tab; everything that used to sit in the More sheet is an app too.
/// Add a screen to the Phone by adding a case, its icon (`Glyph`) and its destination in `PhoneAppScreen`.
enum PhoneApp: String, CaseIterable, Hashable, Identifiable {
    case bank, inbox, news, weather, stats, goals, world, luxury, ventures, richList, reports, achievements, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .bank: return "Bank"
        case .inbox: return "Inbox"
        case .news: return "News"
        case .weather: return "Weather"
        case .stats: return "Stats"
        case .goals: return "Goals"
        case .world: return "World"
        case .luxury: return "Luxury"
        case .ventures: return "Ventures"
        case .richList: return "Rich list"
        case .reports: return "Reports"
        case .achievements: return "Achievements"
        case .settings: return "Settings"
        }
    }

    /// The icon from the approved Phone mockup.
    var glyph: String {
        switch self {
        case .bank: return Glyph.bank
        case .inbox: return Glyph.inbox
        case .news: return Glyph.news
        case .weather: return Glyph.cloud
        case .stats: return Glyph.stats
        case .goals: return Glyph.goals
        case .world: return Glyph.world
        case .luxury: return Glyph.luxury
        case .ventures: return Glyph.ventures
        case .richList: return Glyph.richList
        case .reports: return Glyph.reports
        case .achievements: return Glyph.achievements
        case .settings: return Glyph.settings
        }
    }

    /// The grey line under the app's title.
    var subtitle: String {
        switch self {
        case .bank: return "Accounts, savings and loans"
        case .inbox: return "Decisions, offers and warnings"
        case .news: return "Headlines and the business paper"
        case .weather: return "Conditions, forecast and warnings"
        case .stats: return "Your record and the account log"
        case .goals: return "What to aim for next"
        case .world: return "Public image, rivals and rankings"
        case .luxury: return "Cars, watches, art, yachts, jets and homes"
        case .ventures: return "Startups, funds and stakes"
        case .richList: return "Where you stand among the richest"
        case .reports: return "Weekly, monthly and yearly"
        case .achievements: return "Trophies and awards"
        case .settings: return "How much you decide, saving, haptics"
        }
    }
}

extension PhoneApp {
    /// The muted colour inside the app's icon (Ivory Ledger tints, never loud). The glyph and the label always stay, so colour is never alone.
    var tint: Color {
        switch self {
        case .bank: return Color(hex: 0x8DB89B)
        case .inbox: return Color(hex: 0xD6B889)
        case .news: return Color(hex: 0xB8A58C)
        case .weather: return Color(hex: 0x8FB0C4)
        case .stats: return Color(hex: 0x9AA7C4)
        case .goals: return Color(hex: 0xC9A38C)
        case .world: return Color(hex: 0x7FB3B0)
        case .luxury: return Color(hex: 0xC4A3B4)
        case .ventures: return Color(hex: 0xB5B07E)
        case .richList: return Color(hex: 0xD0A86F)
        case .reports: return Color(hex: 0xA39BC2)
        case .achievements: return Color(hex: 0xC9B07A)
        case .settings: return Color(hex: 0xA19B8F)
        }
    }
}

/// A page of an app that has several (Stats and Activity, Goals and Achievements, the three World pages). The existing screens are
/// reused unchanged; the app is a table with one row per page, each opening that page.
enum PhonePage: String, Hashable, Identifiable {
    case stats = "Stats", activity = "Activity"
    case goals = "Goals", achievements = "Achievements"
    case around = "Around you", biggest = "Biggest companies", records = "Records"
    var id: String { rawValue }

    var glyph: String {
        switch self {
        case .stats: return Glyph.stats
        case .activity: return Glyph.list
        case .goals: return Glyph.goals
        case .achievements: return Glyph.achievements
        case .around: return Glyph.world
        case .biggest: return Glyph.building
        case .records: return Glyph.reports
        }
    }

    var note: String {
        switch self {
        case .stats: return "Your figures and how they moved"
        case .activity: return "What you did, week by week"
        case .goals: return "What you are working towards"
        case .achievements: return "Trophies and awards"
        case .around: return "Cities, circles and where you are"
        case .biggest: return "The biggest companies, ranked"
        case .records: return "Rival, Top 50, monthly results, crises"
        }
    }
}
