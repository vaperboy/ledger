import SwiftUI
import Simulation

/// On a week report: watch an ad and the grant paid this week is paid once more (capped), as its own line on the bank statement.
/// Shown only to free players, outside the first four weeks, once a game week and three times a real day (`AdCoordinator.doubleOffer`).
struct DoubleGrantLink: View {
    @EnvironmentObject private var store: GameStore
    @Environment(AdCoordinator.self) private var ads
    @State private var paidLine: String?

    var body: some View {
        if let extra = ads.doubleOffer(store) {
            Button {
                Haptics.tap()
                Task {
                    let paid: Double = await ads.watchForDouble(store)
                    if paid > 0 { paidLine = "Paid \(store.money(paid)) into your account." }
                }
            } label: {
                Text("Watch an ad: double this week's grant, +\(store.money(extra))")
            }
            .buttonStyle(PopupTextActionStyle(tint: PopupTone.prestige.color))
            .disabled(ads.isShowing)
            .accessibilityIdentifier("report-double-grant")
        } else if let line = paidLine {
            Text(line).textStyle(.caption, tint: Theme.gain)
        }
    }
}

/// On the game-over screen: watch an ad and the game reopens with a fresh stake. Once per save, free players only (`AdCoordinator.secondChanceOffer`).
struct SecondChanceOffer: View {
    @EnvironmentObject private var store: GameStore
    @Environment(AdCoordinator.self) private var ads

    var body: some View {
        if let stake = ads.secondChanceOffer(store) {
            VStack(spacing: Theme.Space.xs) {
                Button("Watch an ad for a second chance") {
                    Haptics.tap()
                    Task { await ads.watchForSecondChance(store) }
                }
                .buttonStyle(TertiaryButtonStyle())
                .disabled(ads.isShowing)
                .accessibilityIdentifier("game-over-second-chance")
                Text("A fresh stake of \(store.money(stake)) and a clear overdraft count. Once per game.")
                    .textStyle(.caption, tint: Theme.inkFaint).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
