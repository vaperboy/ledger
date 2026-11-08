import SwiftUI
import GameCore
import Countries
import Businesses
import Finance
import Events
import Simulation

/// Back a startup from a pitch: pick the amount, read the engine's quote (share, valuation, board seat, cash left), then confirm. The quote
/// rounds the amount to 10,000, caps it at the round and gives the verdict the investment will get.
struct BackStartupSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var pitchID: Int
    @State private var amount = 0.0
    @State private var pending: PendingAction?

    var body: some View {
        Group {
            if let e = store.engine, let p = e.startupPitchesOnOffer.first(where: { (x: Startups.Pitch) -> Bool in x.id == pitchID }) {
                content(e, p)
            } else {
                Text("This pitch is no longer open.").popupText(.body)
            }
        }
        .confirmAction($pending)
        .centerSheetTitle("Back a startup")
    }

    private func content(_ e: GameEngine, _ p: Startups.Pitch) -> some View {
        let cur: Currency = e.homeCurrency
        let lo: Double = e.startupInvestQuote(pitchID: p.id, amount: p.raise).minimum
        let hi: Double = p.raise
        let canChoose: Bool = hi > lo
        let shown = Binding<Double>(get: { min(max(amount, lo), max(lo, hi)) }, set: { (v: Double) in amount = v })
        let q: Startups.InvestQuote = e.startupInvestQuote(pitchID: p.id, amount: shown.wrappedValue)
        let enough: Bool = q.result != .notEnoughMoney
        let pct: String = String(format: "%.1f%%", q.ownershipPercent)
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(p.name).popupText(.figure)
            Text("\(p.sector). \(p.blurb)").popupText(.caption).fixedSize(horizontal: false, vertical: true)
            PopupRow(label: "Raising", value: cur.tidyShort(p.raise))
            PopupRow(label: "Valued at", value: cur.tidyShort(q.postMoney) + " after the money")
            PopupRow(label: "Team \u{00B7} market \u{00B7} traction", value: "\(p.team) \u{00B7} \(p.market) \u{00B7} \(p.traction)")
            if canChoose {
                LedgerSlider(value: shown, in: lo...hi, step: 10000, valueText: "Put in " + cur.tidyShort(q.amount))
                    .accessibilityIdentifier("ventures-back-amount")
            } else {
                Text("This round is smaller than the smallest cheque, \(cur.tidyShort(lo)).").popupText(.risk)
            }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                PopupRow(label: "Price", value: cur.tidyShort(q.amount))
                PopupRow(label: "You get", value: pct)
                PopupRow(label: "Board seat", value: q.boardSeat ? "Yes" : "No, from 20%")
                PopupRow(label: "Your cash after", value: enough ? cur.tidyShort(q.available - q.amount) : "Not enough")
                Text("Most startups fail and the money is lost. Later rounds make your share smaller. You can sell part of a stake later at a discount to its value.")
                    .popupText(.caption).fixedSize(horizontal: false, vertical: true)
                if !enough { Text("You need \(cur.tidyShort(q.amount - q.available)) more in cash.").popupText(.risk) }
                Button("Invest \(cur.tidyShort(q.amount)) for \(pct)") { ask(p, q, cur) }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .disabled(q.result != .ok)
                    .accessibilityIdentifier("ventures-back-go")
            }
        }
    }

    private func ask(_ p: Startups.Pitch, _ q: Startups.InvestQuote, _ cur: Currency) {
        let put: Double = q.amount
        let pct: String = String(format: "%.1f%%", q.ownershipPercent)
        let seat: String = q.boardSeat ? " You get a board seat." : ""
        pending = PendingAction(title: "Back \(p.name)?",
                                message: "\(cur.tidyDisplay(put)) leaves your cash now for \(pct) at a valuation of \(cur.tidyShort(q.postMoney)).\(seat)",
                                button: "Invest \(cur.tidyShort(put))", amount: put, currency: cur,
                                risk: "Most startups fail and the money is lost.", tone: .investment, icon: "chart.pie") {
            switch store.act({ $0.investInStartup(pitchID: p.id, amount: put) }) {
            case .ok?: Haptics.success(); store.show("You now hold \(pct) of \(p.name).", tone: "good"); dismiss()
            case .tooSmall?: store.show("That is below the smallest cheque.", tone: "warn")
            case .notEnoughMoney?: Haptics.warning(); store.show("You need \(cur.tidyShort(put)) in cash.", tone: "warn")
            default: store.show("That pitch has gone.", tone: "warn"); dismiss()
            }
        }
    }
}

/// Sell part or all of a stake in someone else's startup. The engine quotes the proceeds; the owner may ask for 0.5 to 1.4 times that and the
/// buyer sells at the ask, counters, or declines with a reason.
struct SellStakeSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var stakeID: Int
    @State private var fraction = 0.5
    @State private var multiplier = 1.0
    @State private var reply: VentureSale.Outcome?
    @State private var pending: PendingAction?

    var body: some View {
        Group {
            if let e = store.engine, let st = e.startupStakes.first(where: { (x: Startups.Stake) -> Bool in x.id == stakeID && x.live }) {
                content(e, st)
            } else {
                Text("This stake is no longer held.").popupText(.body)
            }
        }
        .confirmAction($pending)
        .centerSheetTitle("Sell shares")
    }

    private func content(_ e: GameEngine, _ st: Startups.Stake) -> some View {
        let cur: Currency = e.homeCurrency
        let q: VentureSale.Quote = e.startupStakeSellQuote(stakeID: st.id, fraction: fraction)
        let ask: Double = (q.proceeds * multiplier).rounded()
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(st.name).popupText(.figure)
            PopupRow(label: "You hold", value: String(format: "%.1f%% worth ", st.ownership) + cur.tidyShort(st.value))
            SegmentedPill(items: [0.25, 0.5, 0.75, 1.0], title: { (f: Double) -> String in "\(Int((f * 100).rounded()))%" }, selection: $fraction)
            if q.ok {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    PopupRow(label: "Fair value of these shares", value: cur.tidyShort(q.fairValue))
                    PopupRow(label: "Buyer pays at the quote", value: cur.tidyShort(q.proceeds))
                    VenturesAskControl(quote: q, cur: cur, multiplier: $multiplier)
                    PopupRow(label: "Against what you put in", value: (ask >= q.costBasis ? "+" : "\u{2212}") + cur.tidyShort(abs(ask - q.costBasis)))
                    PopupRow(label: "You hold after", value: q.closesStake ? "Nothing" : String(format: "%.1f%%", q.remainingPercent))
                    Text("Shares sold early go for \(Int(((1 - q.factor) * 100).rounded()))% under their fair value. A gain is taxed." + (st.boardSeat && !q.keepsBoardSeat && !q.closesStake ? " Under 20% you lose the board seat." : ""))
                        .popupText(.caption).fixedSize(horizontal: false, vertical: true)
                    VenturesSaleReply(reply: reply, cur: cur) { (c: Double) in sell(st, cur, multiplier: c / max(1, q.proceeds)) }
                    Button("Ask \(cur.tidyShort(ask))") { askConfirm(st, q, ask, cur) }.buttonStyle(PrimaryButtonStyle(fullWidth: true))
                        .accessibilityIdentifier("ventures-sell-go")
                }
            } else {
                Text(q.reason).popupText(.risk).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: fraction) { _, _ in reply = nil }
    }

    private func askConfirm(_ st: Startups.Stake, _ q: VentureSale.Quote, _ ask: Double, _ cur: Currency) {
        let m: Double = multiplier
        pending = PendingAction(title: "Sell \(Int((q.fraction * 100).rounded()))% of your stake in \(st.name)?",
                                message: "You ask \(cur.tidyShort(ask)). The buyer may take it, offer less, or refuse. A sale cannot be undone.",
                                button: "Sell", destructive: true, tone: .investment, icon: "arrow.up.right") {
            sell(st, cur, multiplier: m)
        }
    }

    private func sell(_ st: Startups.Stake, _ cur: Currency, multiplier m: Double) {
        let f: Double = fraction
        let id: Int = st.id
        let out: VentureSale.Outcome = store.act { (e: inout GameEngine) -> VentureSale.Outcome in
            e.sellStartupStake(stakeID: id, fraction: f, askingMultiplier: m)
        } ?? .unavailable("That stake could not be sold.")
        if case .sold(let v) = out {
            Haptics.success(); store.show("Sold for \(cur.tidyShort(v)).", tone: "good"); dismiss()
        } else {
            Haptics.warning(); reply = out
        }
    }
}
