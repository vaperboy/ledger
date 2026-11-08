import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// A percentage as the holding screens show it: whole when it is whole, one decimal otherwise.
func holdingPct(_ p: Double) -> String {
    p == p.rounded() ? "\(Int(p))%" : String(format: "%.1f%%", p)
}

/// The confirmation for moving money from the player's account into the holding's account.
@MainActor
func holdingInjectAction(store: GameStore, holdingID: Int, holdingName: String, amount: Double, cur: Currency) -> PendingAction {
    PendingAction(title: "Put \(cur.tidyShort(amount)) into \(holdingName)?", message: "The money moves from your personal account into the holding's own account. It stays there until the holding spends it.",
                  button: "Put in", amount: amount, currency: cur) {
        let ok: Bool = store.act { (e: inout GameEngine) -> Bool in e.putMoneyInto(companyID: holdingID, amount: amount) } ?? false
        if ok { Haptics.success() } else { Haptics.warning() }
        store.show(ok ? "\(cur.tidyShort(amount)) is now in \(holdingName)." : "You don't have that much available.", tone: ok ? "good" : "warn")
    }
}

/// What a stake tier means, in the plain words the engine gives it, with the percent it sits at.
struct HoldingTierNote: View {
    var tier: HoldingStakes.Tier
    var percent: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(tier.title) at \(holdingPct(percent))").popupText(.rowLabel)
            Text(tier.summary).popupText(.caption).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The four ranges, so a player knows what a share buys before choosing one.
struct HoldingTierLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Under 20%: passive. Dividends only, no board seat.").popupText(.caption)
            Text("20% to 50%: influence. May take a board seat.").popupText(.caption)
            Text("Over 50%: control. Consolidated, votes at the board.").popupText(.caption)
            Text("90% or more: may buy out the rest and merge the company in.").popupText(.caption)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A holding's cash against what a deal needs, with a button to put the missing part in from the personal account.
struct HoldingCashNeed: View {
    var holdingCash: Double
    var needed: Double
    var cur: Currency
    var onInject: (Double) -> Void

    var body: some View {
        let short: Double = max(0, (needed - holdingCash).rounded(.up))
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            PopupRow(label: "Cash in the holding", value: cur.tidyShort(holdingCash))
            if short > 0 {
                Text("The holding is \(cur.tidyShort(short)) short for this. It pays from its own account.").popupText(.risk)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Put \(cur.tidyShort(short)) into the holding") { onInject(short) }
                    .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                    .accessibilityIdentifier("holding-inject")
            }
        }
    }
}
