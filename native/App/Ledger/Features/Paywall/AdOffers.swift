import SwiftUI
import Simulation

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
