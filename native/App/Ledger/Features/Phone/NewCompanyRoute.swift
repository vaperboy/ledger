import SwiftUI
import GameCore
import Simulation

/// What the player has done across every game on this device (the player-level profile, kept in UserDefaults, not in a save).
enum PlayerHistory {
    static let companiesKey = "ledger.profile.companiesStarted"

    static var companiesStarted: Int { UserDefaults.standard.integer(forKey: companiesKey) }

    /// A company was registered, in any game.
    static func noteStarted() { UserDefaults.standard.set(companiesStarted + 1, forKey: companiesKey) }

    /// True for the player's very first company: none was ever started on this device, and the game in play has none. A game that already
    /// holds companies (an install from before the count) counts them, so the guided start is never offered again.
    static func isFirstCompany(_ e: GameEngine) -> Bool {
        let held: Int = e.state.companies.filter { (c: Company) -> Bool in c.type != "hold" }.count
        if held > companiesStarted { UserDefaults.standard.set(held, forKey: companiesKey) }
        return companiesStarted == 0
    }
}

/// Where "New company" goes: the guided start (three questions, honest cost, payback and risk) for the player's first company ever, the full
/// create-company flow (every choice: name, premises, set-up, accountant, franchise) for every company after it and in every later game.
struct NewCompanyRoute: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        if let e = store.engine, PlayerHistory.isFirstCompany(e) { GuidedStartView() } else { NewCompanyView() }
    }
}
