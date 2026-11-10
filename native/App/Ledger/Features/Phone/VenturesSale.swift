import SwiftUI
import GameCore
import Countries
import Events

struct VenturesAskControl: View {
    var quote: VentureSale.Quote
    var cur: Currency
    @Binding var multiplier: Double

    var body: some View {
        let m: Double = snapped(multiplier)
        let shown = Binding<Double>(get: { snapped(multiplier) }, set: { (v: Double) in multiplier = snapped(v) })
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            LedgerSlider(value: shown, in: VentureSale.askLowest...VentureSale.askHighest, step: 0.05,
                         valueText: "Ask " + cur.tidyShort(quote.proceeds * m) + String(format: " (%.2f\u{00D7})", m))
                .accessibilityIdentifier("ventures-ask")
            PopupRow(label: "Range you may ask", value: cur.tidyShort(quote.askLowest) + " to " + cur.tidyShort(quote.askHighest))
            Text(m > 1.0001 ? "Above the quote the buyer may refuse, offer less, or walk away. A refusal closes the talks until next week."
                 : m < 0.9999 ? "Below the quote a buyer takes it at once." : "The quoted price: a buyer takes it at once.")
                .popupText(.caption).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func snapped(_ v: Double) -> Double {
        (min(max(v, VentureSale.askLowest), VentureSale.askHighest) * 100).rounded() / 100
    }
}

struct VenturesSaleReply: View {
    var reply: VentureSale.Outcome?
    var cur: Currency
    var take: (Double) -> Void

    var body: some View {
        switch reply {
        case .counter(let c)?:
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("The buyer offers \(cur.tidyShort(c)) instead, the most they will pay this week.").popupText(.rowLabel)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Take \(cur.tidyShort(c))") { take(c) }.buttonStyle(SecondaryButtonStyle(fullWidth: true))
                    .accessibilityIdentifier("ventures-take-counter")
            }
        case .declined(let why)?, .unavailable(let why)?:
            Text(why).popupText(.risk).fixedSize(horizontal: false, vertical: true)
        default:
            EmptyView()
        }
    }
}
