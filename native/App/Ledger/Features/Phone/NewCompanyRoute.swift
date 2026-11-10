import SwiftUI
import GameCore
import Simulation

enum PlayerHistory {
    static let companiesKey = "ledger.profile.companiesStarted"

    static var companiesStarted: Int { UserDefaults.standard.integer(forKey: companiesKey) }

    static func noteStarted() { UserDefaults.standard.set(companiesStarted + 1, forKey: companiesKey) }

    static func isFirstCompany(_ e: GameEngine) -> Bool {
        let held: Int = e.state.companies.filter { (c: Company) -> Bool in c.type != "hold" }.count
        if held > companiesStarted { UserDefaults.standard.set(held, forKey: companiesKey) }
        return companiesStarted == 0
    }
}

struct NewCompanyRoute: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        if let e = store.engine, PlayerHistory.isFirstCompany(e) { GuidedStartView() } else { NewCompanyView() }
    }
}
