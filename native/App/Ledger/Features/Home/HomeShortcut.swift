import SwiftUI
import GameCore
import Simulation

/// Shortcuts to Phone apps and flows (up to four). The engine stores the identifiers per game
/// (`GameEngine.homeShortcutIDs`); what each one opens lives here.
enum HomeShortcut: String, CaseIterable, Identifiable {
    case bank, hire, reports, market, inbox, accounting, goals, news, stats, ventures
    var id: String { rawValue }

    static let defaults: [HomeShortcut] = [.bank, .hire, .reports, .market]

    var title: String {
        switch self {
        case .bank: return "Bank"
        case .hire: return "Hire"
        case .reports: return "Reports"
        case .market: return "Market"
        case .inbox: return "Inbox"
        case .accounting: return "Accounting"
        case .goals: return "Goals"
        case .news: return "News"
        case .stats: return "Stats"
        case .ventures: return "Ventures"
        }
    }

    var glyph: String {
        switch self {
        case .bank: return Glyph.bank
        case .hire: return Glyph.hire
        case .reports: return Glyph.reports
        case .market: return Glyph.market
        case .inbox: return PhoneApp.inbox.glyph
        case .accounting: return PhoneApp.accounting.glyph
        case .goals: return PhoneApp.goals.glyph
        case .news: return PhoneApp.news.glyph
        case .stats: return PhoneApp.stats.glyph
        case .ventures: return PhoneApp.ventures.glyph
        }
    }

    /// The Phone app whose red bubble this box carries, if it has one.
    var badgeApp: PhoneApp? {
        switch self {
        case .inbox: return .inbox
        case .accounting: return .accounting
        default: return nil
        }
    }

    @MainActor func open(_ store: GameStore) {
        switch self {
        case .bank: store.openApp(.bank)
        case .hire: store.openHiring()
        case .reports: store.openApp(.reports)
        case .market: store.openMarket()
        case .inbox: store.openApp(.inbox)
        case .accounting: store.openApp(.accounting)
        case .goals: store.openApp(.goals)
        case .news: store.openApp(.news)
        case .stats: store.openApp(.stats)
        case .ventures: store.openApp(.ventures)
        }
    }

    /// The saved identifiers as shortcuts: unknown ones are dropped, and with nothing saved (or nothing valid) the default four.
    static func resolve(_ ids: [String]?) -> [HomeShortcut] {
        guard let ids else { return defaults }
        let list: [HomeShortcut] = ids.compactMap { HomeShortcut(rawValue: $0) }
        return list.isEmpty ? defaults : Array(list.prefix(4))
    }
}

/// What the last ordinary day did, in real figures: shown beside the week progress after Next day.
struct DayChip: Equatable, Identifiable {
    var id: UUID
    /// The day of the week that has just been reached (1 to 7).
    var day: Int
    var netWorthChange: Double
    var cashChange: Double
    /// The group's profit on that day (nil when it could not be measured).
    var profit: Double? = nil
}
