import SwiftUI
import GameCore
import Simulation

/// Shown when the bank has taken everything. The save is kept; the player can look around or start again.
struct GameOverView: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine

    var body: some View {
        let over = engine.state.gameOver
        VStack(spacing: Theme.Space.l) {
            Image(systemName: "building.columns").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(Theme.roseGold)
            Text("The ledger is closed").font(.system(.title, design: .serif).weight(.semibold))
            Text(over["reason"].string == "insolvent"
                 ? "You owe more than you own and the bank has ended it."
                 : "Your account stayed empty for too long. The bank has stopped lending.")
                .font(.bodyText).foregroundStyle(Theme.ivoryMuted).multilineTextAlignment(.center)
            Text("Week \(over["week"].int + 1) · best net worth \(store.money(engine.state.stats.peakNetWorth))").font(.label).foregroundStyle(Theme.ivoryFaint)
            Button("Start again") { store.quitToMenu() }.buttonStyle(GoldButtonStyle()).padding(.top, Theme.Space.m)
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ledgerBackground()
    }
}
