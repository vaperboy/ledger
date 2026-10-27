import SwiftUI

/// The apps on the Phone home screen. Inbox is an app here, not a tab; everything that used to sit in the More sheet is an app too.
/// Add a screen to the Phone by adding a case, its icon (`Glyph`) and its destination in `PhoneAppScreen`.
enum PhoneApp: String, CaseIterable, Hashable, Identifiable {
    case bank, inbox, news, stats, goals, world, luxury, ventures, richList, reports, achievements, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .bank: return "Bank"
        case .inbox: return "Inbox"
        case .news: return "News"
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
        case .news: return "What is happening around you"
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

/// A page of an app that has several (Stats and Activity, Goals and Achievements, the three World pages). The existing screens are
/// reused unchanged; the app puts a `SegmentedPill` above them.
enum PhonePage: String, Hashable {
    case stats = "Stats", activity = "Activity"
    case goals = "Goals", achievements = "Achievements"
    case around = "Around you", biggest = "Biggest companies", records = "Records"
}
