import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Events
import Simulation

/// The holding backs a startup from a pitch: amount, the engine's quote (share, valuation, tier reached), cash check, then confirm.
struct HoldingBackStartupSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var holdingID: Int
    var pitchID: Int
    @State private var amount = 0.0
    @State private var pending: PendingAction?

    var body: some View {
        Group {
            if let e = store.engine, let h = e.state.company(holdingID), let p = e.startupPitchesOnOffer.first(where: { (x: Startups.Pitch) -> Bool in x.id == pitchID }) {
                content(e, h, p)
            } else {
                Text("This pitch is no longer open.").popupText(.body)
            }
        }
        .confirmAction($pending)
        .centerSheetTitle("Back a startup")
    }

    private func content(_ e: GameEngine, _ h: Company, _ p: Startups.Pitch) -> some View {
        let cur: Currency = e.currency(for: h)
        let lo: Double = e.startupInvestQuote(pitchID: p.id, amount: p.raise).minimum
        let hi: Double = p.raise
        let shown = Binding<Double>(get: { min(max(amount, lo), max(lo, hi)) }, set: { (v: Double) in amount = v })
        let result = e.holdingStartupInvestQuote(holdingID: holdingID, pitchID: p.id, amount: shown.wrappedValue)
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(p.name).popupText(.figure)
            Text("\(p.sector). \(p.blurb)").popupText(.caption).fixedSize(horizontal: false, vertical: true)
            PopupRow(label: "Raising", value: cur.tidyShort(p.raise))
            PopupRow(label: "Valued at", value: cur.tidyShort(p.postMoney) + " after the money")
            if hi > lo {
                LedgerSlider(value: shown, in: lo...hi, step: 10000, valueText: "Put in " + cur.tidyShort(shown.wrappedValue))
                    .accessibilityIdentifier("holding-startup-amount")
            } else {
                Text("This round is smaller than the smallest cheque, \(cur.tidyShort(lo)).").popupText(.risk)
            }
            switch result {
            case .success(let q):
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    PopupRow(label: "Price", value: cur.tidyShort(q.amount))
                    HoldingTierNote(tier: HoldingStakes.tier(forPercent: q.ownershipPercent), percent: q.ownershipPercent)
                    Text("Most startups fail and the money is lost. Later rounds make the holding's share smaller.").popupText(.caption).fixedSize(horizontal: false, vertical: true)
                    HoldingCashNeed(holdingCash: h.cash, needed: q.amount, cur: cur) { (short: Double) in
                        pending = holdingInjectAction(store: store, holdingID: holdingID, holdingName: h.name, amount: short, cur: cur)
                    }
                    Button("Invest \(cur.tidyShort(q.amount)) for \(holdingPct((q.ownershipPercent * 10).rounded() / 10))") { ask(p, q, h.name, cur) }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                        .accessibilityIdentifier("holding-startup-back-go")
                }
            case .failure(let f):
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text(f.reason).popupText(.risk).fixedSize(horizontal: false, vertical: true)
                    if case .notEnoughCash(let needed) = f {
                        HoldingCashNeed(holdingCash: h.cash, needed: needed, cur: cur) { (short: Double) in
                            pending = holdingInjectAction(store: store, holdingID: holdingID, holdingName: h.name, amount: short, cur: cur)
                        }
                    }
                }
            }
        }
    }

    private func ask(_ p: Startups.Pitch, _ q: Startups.InvestQuote, _ holdingName: String, _ cur: Currency) {
        let put: Double = q.amount
        let pct: String = holdingPct((q.ownershipPercent * 10).rounded() / 10)
        let hid: Int = holdingID
        pending = PendingAction(title: "Back \(p.name)?",
                                message: "\(holdingName) pays \(cur.tidyShort(put)) from its own account for \(pct) at a valuation of \(cur.tidyShort(q.postMoney)).",
                                button: "Invest \(cur.tidyShort(put))", amount: put, currency: cur,
                                risk: "Most startups fail and the money is lost.", tone: .investment, icon: "chart.pie") {
            let r: Result<StartupHolding.Deal, HoldingStakes.Failure>? = store.act { (eng: inout GameEngine) -> Result<StartupHolding.Deal, HoldingStakes.Failure> in
                eng.holdingInvestInStartup(holdingID: hid, pitchID: p.id, amount: put)
            }
            switch r {
            case .success(let d)?: Haptics.success(); store.show("The holding now owns \(holdingPct((d.heldAfter * 10).rounded() / 10)) of \(p.name).", tone: "good"); dismiss()
            case .failure(let f)?: Haptics.warning(); store.show(f.reason, tone: "warn")
            case nil: store.show("It could not be bought now.", tone: "warn")
            }
        }
    }
}

/// The holding buys more of a startup it already holds: percent, price with the premium or discount for the tier it reaches, cash check.
struct HoldingBuyMoreStartupSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var holdingID: Int
    var stakeID: Int
    @State private var percent = 5.0
    @State private var pending: PendingAction?

    var body: some View {
        Group {
            if let e = store.engine, let h = e.state.company(holdingID),
               let s = e.holdingStartupStakes(holdingID: holdingID).first(where: { (x: StartupHolding.Stake) -> Bool in x.id == stakeID && x.live }) {
                content(e, h, s)
            } else {
                Text("This stake is no longer held.").popupText(.body)
            }
        }
        .confirmAction($pending)
        .centerSheetTitle("Buy more shares")
    }

    private func content(_ e: GameEngine, _ h: Company, _ s: StartupHolding.Stake) -> some View {
        let cur: Currency = e.currency(for: h)
        let lo: Double = HoldingStakes.minimumPercent
        let hi: Double = max(lo, min(100 - s.percent, 100))
        let shown = Binding<Double>(get: { min(max(percent, lo), hi) }, set: { (v: Double) in percent = v })
        let result = e.holdingStartupBuyMoreQuote(holdingID: holdingID, stakeID: s.id, percent: shown.wrappedValue)
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(s.name).popupText(.figure)
            PopupRow(label: "The startup is worth", value: cur.tidyShort(s.valuation))
            HoldingTierNote(tier: s.tier, percent: s.percent)
            HoldingTierLegend()
            if hi > lo {
                LedgerSlider(value: shown, in: lo...hi, step: 0.5, valueText: "Buy " + holdingPct(shown.wrappedValue))
                    .accessibilityIdentifier("holding-startup-more-percent")
            }
            switch result {
            case .success(let q):
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    PopupRow(label: "Price", value: cur.tidyShort(q.price))
                    PopupRow(label: "Fair value of these shares", value: cur.tidyShort(q.valuation * q.percent / 100))
                    if q.priceFactor > 1.0001 { Text("Includes a \(Int(saturating: ((q.priceFactor - 1) * 100).rounded()))% premium for taking control.").popupText(.caption) }
                    if q.priceFactor < 0.9999 { Text("A small stake is bought at a \(Int(saturating: ((1 - q.priceFactor) * 100).rounded()))% discount.").popupText(.caption) }
                    HoldingTierNote(tier: q.tierAfter, percent: q.heldAfter)
                    HoldingCashNeed(holdingCash: h.cash, needed: q.price, cur: cur) { (short: Double) in
                        pending = holdingInjectAction(store: store, holdingID: holdingID, holdingName: h.name, amount: short, cur: cur)
                    }
                    Button("Buy \(holdingPct(q.percent)) for \(cur.tidyShort(q.price))") { ask(s, q, h.name, cur) }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                        .disabled(h.cash < q.price)
                        .accessibilityIdentifier("holding-startup-more-go")
                }
            case .failure(let f):
                Text(f.reason).popupText(.risk).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func ask(_ s: StartupHolding.Stake, _ q: StartupHolding.MoreQuote, _ holdingName: String, _ cur: Currency) {
        let pct: Double = q.percent
        let hid: Int = holdingID
        let sid: Int = s.id
        pending = PendingAction(title: "Buy \(holdingPct(pct)) of \(s.name)?",
                                message: "\(holdingName) pays \(cur.tidyShort(q.price)) from its own account and then owns \(holdingPct((q.heldAfter * 10).rounded() / 10)): \(q.tierAfter.title.lowercased()).",
                                button: "Buy", amount: q.price, currency: cur, tone: .investment, icon: "chart.pie") {
            let r: Result<StartupHolding.Deal, HoldingStakes.Failure>? = store.act { (eng: inout GameEngine) -> Result<StartupHolding.Deal, HoldingStakes.Failure> in
                eng.holdingBuyMoreOfStartup(holdingID: hid, stakeID: sid, percent: pct)
            }
            switch r {
            case .success(let d)?: Haptics.success(); store.show("The holding now owns \(holdingPct((d.heldAfter * 10).rounded() / 10)) of \(s.name).", tone: "good"); dismiss()
            case .failure(let f)?: Haptics.warning(); store.show(f.reason, tone: "warn")
            case nil: store.show("It could not be bought now.", tone: "warn")
            }
        }
    }
}

/// The holding sells part or all of a startup stake: the quote by tier, an asking price, the buyer's counter-offer or reason for declining.
struct HoldingSellStartupSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var holdingID: Int
    var stakeID: Int
    @State private var fraction = 0.5
    @State private var multiplier = 1.0
    @State private var reply: VentureSale.Outcome?
    @State private var pending: PendingAction?

    var body: some View {
        Group {
            if let e = store.engine, let h = e.state.company(holdingID),
               let s = e.holdingStartupStakes(holdingID: holdingID).first(where: { (x: StartupHolding.Stake) -> Bool in x.id == stakeID && x.live }) {
                content(e, h, s)
            } else {
                Text("This stake is no longer held.").popupText(.body)
            }
        }
        .confirmAction($pending)
        .centerSheetTitle("Sell shares")
    }

    private func content(_ e: GameEngine, _ h: Company, _ s: StartupHolding.Stake) -> some View {
        let cur: Currency = e.currency(for: h)
        let result = e.holdingStartupSellQuote(holdingID: holdingID, stakeID: s.id, fraction: fraction)
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(s.name).popupText(.figure)
            HoldingTierNote(tier: s.tier, percent: s.percent)
            SegmentedPill(items: [0.25, 0.5, 0.75, 1.0], title: { (f: Double) -> String in "\(Int(saturating: (f * 100).rounded()))%" }, selection: $fraction)
            switch result {
            case .success(let q):
                let ask: Double = (q.proceeds * multiplier).rounded()
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    PopupRow(label: "Fair value of these shares", value: cur.tidyShort(q.fairValue))
                    PopupRow(label: "Buyer pays at the quote", value: cur.tidyShort(q.proceeds))
                    VenturesAskControl(quote: q, cur: cur, multiplier: $multiplier)
                    PopupRow(label: "Against what the holding paid", value: (ask >= q.costBasis ? "+" : "\u{2212}") + cur.tidyShort(abs(ask - q.costBasis)))
                    PopupRow(label: "The holding keeps", value: q.closesStake ? "Nothing" : holdingPct((q.remainingPercent * 10).rounded() / 10))
                    Text("A buyer pays \(Int(saturating: (q.factor * 100).rounded()))% of fair value at this stake size; a bigger stake is easier to sell. The money goes into the holding's account.")
                        .popupText(.caption).fixedSize(horizontal: false, vertical: true)
                    VenturesSaleReply(reply: reply, cur: cur) { (c: Double) in sell(cur, multiplier: c / max(1, q.proceeds)) }
                    Button("Ask \(cur.tidyShort(ask))") { askConfirm(s, q, ask, cur) }.buttonStyle(PrimaryButtonStyle(fullWidth: true))
                        .accessibilityIdentifier("holding-startup-sell-go")
                }
            case .failure(let f):
                Text(f.reason).popupText(.risk).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: fraction) { _, _ in reply = nil }
    }

    private func askConfirm(_ s: StartupHolding.Stake, _ q: VentureSale.Quote, _ ask: Double, _ cur: Currency) {
        let m: Double = multiplier
        pending = PendingAction(title: "Sell \(Int(saturating: (q.fraction * 100).rounded()))% of the stake in \(s.name)?",
                                message: "The holding asks \(cur.tidyShort(ask)). The buyer may take it, offer less, or refuse. A sale cannot be undone.",
                                button: "Sell", destructive: true, tone: .investment, icon: "arrow.up.right") {
            sell(cur, multiplier: m)
        }
    }

    private func sell(_ cur: Currency, multiplier m: Double) {
        let f: Double = fraction
        let hid: Int = holdingID
        let sid: Int = stakeID
        let r: Result<VentureSale.Outcome, HoldingStakes.Failure>? = store.act { (eng: inout GameEngine) -> Result<VentureSale.Outcome, HoldingStakes.Failure> in
            eng.holdingSellStartupStake(holdingID: hid, stakeID: sid, fraction: f, askingMultiplier: m)
        }
        switch r {
        case .success(let out)?:
            if case .sold(let v) = out { Haptics.success(); store.show("Sold for \(cur.tidyShort(v)).", tone: "good"); dismiss() } else { Haptics.warning(); reply = out }
        case .failure(let why)?: Haptics.warning(); reply = .unavailable(why.reason)
        case nil: reply = .unavailable("That stake could not be sold.")
        }
    }
}
