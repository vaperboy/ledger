import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

struct CompetitionApp: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        Group {
            if store.engine != nil { CompetitionReviews() } else { Color.clear }
        }
        .appScreen(title: "Reviews", subtitle: PhoneApp.competition.subtitle)
        .accessibilityIdentifier("competition-app")
    }

    static func reviewCompanies(_ e: GameEngine) -> [Company] {
        e.state.companies.filter { (co: Company) -> Bool in
            guard co.status == .open, let family = e.tradeInfo(companyID: co.id)?.family else { return false }
            return !["fin", "energy", "club"].contains(family)
        }
    }

    static func lineKey(_ e: GameEngine, _ co: Company, _ l: ReviewLine) -> String {
        "v\(co.id).\(e.state.week - l.weeksAgo).\(l.stars).\(l.who)"
    }
}
