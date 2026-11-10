import SwiftUI
import GameCore
import Simulation

enum HomeShortcut: String, CaseIterable, Identifiable {
    case bank, hire, reports, market, inbox, goals, news, ventures
    var id: String { rawValue }

    static let defaults: [HomeShortcut] = [.bank, .hire, .reports, .market]

    var title: String {
        switch self {
        case .bank: return "Bank"
        case .hire: return "Hire"
        case .reports: return "Reports"
        case .market: return "Market"
        case .inbox: return "Inbox"
        case .goals: return "Goals"
        case .news: return "News"
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
        case .goals: return Glyph.goals
        case .news: return PhoneApp.news.glyph
        case .ventures: return PhoneApp.ventures.glyph
        }
    }

    var badgeApp: PhoneApp? {
        switch self {
        case .inbox: return .inbox
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
        case .goals: store.openGoals()
        case .news: store.openApp(.news)
        case .ventures: store.openApp(.ventures)
        }
    }

    static func resolve(_ ids: [String]?) -> [HomeShortcut] {
        guard let ids else { return defaults }
        let list: [HomeShortcut] = ids.compactMap { HomeShortcut(rawValue: $0) }
        return list.isEmpty ? defaults : Array(list.prefix(4))
    }
}

struct DayChip: Equatable, Identifiable {
    var id: UUID
    var day: Int
    var netWorthChange: Double
    var cashChange: Double
    var profit: Double? = nil
}
