import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// The holding buys shares of other companies, in whole or in part: pick one, choose the percent, read the quote and the tier it reaches,
/// make sure the holding has the cash, then confirm. Own companies and other businesses are listed together.
struct HoldingBuyStakes: View {
    @EnvironmentObject var store: GameStore
    var holdingID: Int
    /// An offer to open straight on ("c:<companyID>"), for "Buy more" on a stake row.
    var startOfferID: String? = nil
    @State private var offerID: String?
    @State private var percent = 5.0
    @State private var pending: PendingAction?

    var body: some View {
        Group {
            if let e = store.engine, let h = e.state.company(holdingID) {
                content(e, h)
            } else {
                Text("This holding is not available.").popupText(.body)
            }
        }
        .confirmAction($pending)
        .centerSheetTitle("Buy stakes")
        .onAppear { openStartOffer() }
    }

    private func openStartOffer() {
        guard offerID == nil, let id = startOfferID, let e = store.engine,
              let o = e.holdingStakeOffers(holdingID: holdingID).first(where: { (x: HoldingStakes.Offer) -> Bool in x.id == id }) else { return }
        percent = min(max(5, HoldingStakes.minimumPercent), max(HoldingStakes.minimumPercent, o.availablePercent))
        offerID = o.id
    }

    @ViewBuilder private func content(_ e: GameEngine, _ h: Company) -> some View {
        let offers: [HoldingStakes.Offer] = e.holdingStakeOffers(holdingID: holdingID)
        let cur: Currency = e.currency(for: h)
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if let id = offerID, let o = offers.first(where: { (x: HoldingStakes.Offer) -> Bool in x.id == id }) {
                detail(e, h, o, cur)
            } else {
                list(offers, h, cur)
            }
        }
    }

    // MARK: The list

    private func list(_ offers: [HoldingStakes.Offer], _ h: Company, _ cur: Currency) -> some View {
        let own: [HoldingStakes.Offer] = offers.filter { (o: HoldingStakes.Offer) -> Bool in o.isOwn }
        let others: [HoldingStakes.Offer] = offers.filter { (o: HoldingStakes.Offer) -> Bool in !o.isOwn }
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Cash in the holding: \(cur.tidyShort(h.cash))").popupText(.subtitle)
            HoldingTierLegend()
            if offers.isEmpty {
                Text("Nothing is for sale right now.").popupText(.body)
            }
            if !own.isEmpty {
                Text("Your companies").popupText(.subtitle)
                VStack(spacing: 0) { ForEach(own) { (o: HoldingStakes.Offer) in offerRow(o, cur) } }
            }
            if !others.isEmpty {
                Text("Other companies").popupText(.subtitle)
                VStack(spacing: 0) { ForEach(others) { (o: HoldingStakes.Offer) in offerRow(o, cur) } }
            }
        }
    }

    private func offerRow(_ o: HoldingStakes.Offer, _ cur: Currency) -> some View {
        let held: String = o.heldPercent > 0 ? " \u{00B7} holding owns \(holdingPct(o.heldPercent))" : ""
        let line: String = "Worth \(cur.tidyShort(o.value)) \u{00B7} \(cur.tidyShort(o.pricePerPercentMinority)) per 1%\(held)"
        return PopupChoiceRow(title: o.name, subtitle: line, identifier: "holding-offer-\(o.id)") {
            percent = min(max(5, HoldingStakes.minimumPercent), max(HoldingStakes.minimumPercent, o.availablePercent))
            offerID = o.id
        }
    }

    // MARK: One offer

    private func quoteFor(_ e: GameEngine, _ o: HoldingStakes.Offer) -> Result<HoldingStakes.Quote, HoldingStakes.Failure> {
        if let cid = o.companyID { return e.holdingStakeQuote(holdingID: holdingID, companyID: cid, percent: percent) }
        return e.holdingRivalStakeQuote(holdingID: holdingID, rivalID: o.rivalID ?? 0, percent: percent)
    }

    private func detail(_ e: GameEngine, _ h: Company, _ o: HoldingStakes.Offer, _ cur: Currency) -> some View {
        let lo: Double = HoldingStakes.minimumPercent
        let hi: Double = min(100, o.availablePercent)
        let shown = Binding<Double>(get: { min(max(percent, lo), max(lo, hi)) }, set: { (v: Double) in percent = v })
        let result = quoteFor(e, o)
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(o.name).popupText(.figure)
            Text(o.note).popupText(.caption).fixedSize(horizontal: false, vertical: true)
            PopupRow(label: "Worth in all", value: cur.tidyShort(o.value))
            if o.heldPercent > 0 { PopupRow(label: "The holding owns now", value: holdingPct(o.heldPercent)) }
            PopupRow(label: "Available to buy", value: holdingPct(o.availablePercent))
            if hi > lo {
                LedgerSlider(value: shown, in: lo...hi, step: 0.5, valueText: "Buy " + holdingPct(shown.wrappedValue))
                    .accessibilityIdentifier("holding-buy-percent")
            } else {
                Text("Buy \(holdingPct(hi))").popupText(.rowLabel)
            }
            quoteView(e, h, o, result, cur)
            Button("Back to the list") { Haptics.tap(); offerID = nil }.buttonStyle(TertiaryButtonStyle(fullWidth: true))
        }
    }

    @ViewBuilder private func quoteView(_ e: GameEngine, _ h: Company, _ o: HoldingStakes.Offer, _ result: Result<HoldingStakes.Quote, HoldingStakes.Failure>, _ cur: Currency) -> some View {
        switch result {
        case .success(let q):
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                PopupRow(label: "Price", value: cur.tidyShort(q.price))
                PopupRow(label: "Fair value of these shares", value: cur.tidyShort(q.value * q.percent / 100))
                if q.priceFactor > 1.0001 { Text("Includes a \(Int(((q.priceFactor - 1) * 100).rounded()))% premium for taking control.").popupText(.caption) }
                if q.priceFactor < 0.9999 { Text("A small stake is bought at a \(Int(((1 - q.priceFactor) * 100).rounded()))% discount.").popupText(.caption) }
                if q.fromOwnerPercent > 0 && q.fromOthersPercent > 0 {
                    Text("\(holdingPct(q.fromOwnerPercent)) comes from your own shares, \(holdingPct(q.fromOthersPercent)) from other owners.").popupText(.caption)
                } else if q.fromOwnerPercent > 0 {
                    Text("The shares come from you, at fair value.").popupText(.caption)
                }
                HoldingTierNote(tier: q.tierAfter, percent: q.heldAfter)
                HoldingCashNeed(holdingCash: h.cash, needed: q.price, cur: cur) { (short: Double) in
                    pending = holdingInjectAction(store: store, holdingID: holdingID, holdingName: h.name, amount: short, cur: cur)
                }
                Button("Buy \(holdingPct(q.percent)) for \(cur.tidyShort(q.price))") { askBuy(o, q, h.name, cur) }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .disabled(h.cash < q.price)
                    .accessibilityIdentifier("holding-buy-go")
                if h.cash < q.price, let cid = o.companyID { loanOffer(e, h, o.name, cid, q, cur) }
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

    /// When cash is short: the lender's terms for the missing part, or the reason it would refuse.
    @ViewBuilder private func loanOffer(_ e: GameEngine, _ h: Company, _ name: String, _ cid: Int, _ q: HoldingStakes.Quote, _ cur: Currency) -> some View {
        if case .success(let t) = e.holdingBuyLoanQuote(holdingID: holdingID, companyID: cid, percent: q.percent), t.amount > 0 {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Or borrow the difference").popupText(.subtitle)
                PopupRow(label: "Loan", value: cur.tidyShort(t.amount))
                PopupRow(label: "Interest rate", value: String(format: "%.1f%% a year", t.yearlyRate * 100))
                PopupRow(label: "Monthly payment", value: cur.tidyShort(t.monthlyPayment) + " for \(t.termMonths) months")
                PopupRow(label: "Total interest", value: cur.tidyShort(t.totalInterest))
                PopupRow(label: "Most it can borrow now", value: cur.tidyShort(t.maximum))
                PopupRow(label: "Lender", value: t.lender)
                if !t.allowed {
                    Text(t.reason).popupText(.risk).fixedSize(horizontal: false, vertical: true)
                }
                Button("Borrow and buy") { askBorrowBuy(name, cid, q, t, h.name, cur) }
                    .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                    .disabled(!t.allowed)
                    .accessibilityIdentifier("holding-buy-borrow")
            }
        }
    }

    private func askBorrowBuy(_ name: String, _ cid: Int, _ q: HoldingStakes.Quote, _ t: HoldingStakes.BorrowTerms, _ holdingName: String, _ cur: Currency) {
        let pct: Double = q.percent
        pending = PendingAction(title: "Borrow and buy \(holdingPct(pct)) of \(name)?",
                                message: "\(holdingName) borrows \(cur.tidyShort(t.amount)) from \(t.lender) at \(String(format: "%.1f%%", t.yearlyRate * 100)) and pays \(cur.tidyShort(q.price)) in all. The loan is the holding's own: \(cur.tidyShort(t.monthlyPayment)) a month for \(t.termMonths) months comes out of its account.",
                                button: "Borrow and buy", alwaysAsk: true, amount: q.price, currency: cur,
                                risk: "If the holding's account runs dry, the instalments are missed.") {
            let r: Result<HoldingStakes.LoanDeal, HoldingStakes.Failure>? = store.act { (eng: inout GameEngine) -> Result<HoldingStakes.LoanDeal, HoldingStakes.Failure> in
                eng.holdingBuyStakeWithLoan(holdingID: holdingID, companyID: cid, percent: pct)
            }
            switch r {
            case .success(let d)?:
                Haptics.success()
                store.show("Bought \(holdingPct(d.deal.percent)) of \(name) with a loan of \(cur.tidyShort(d.borrowed)). The holding now owns \(holdingPct(d.deal.heldAfter)).", tone: "good")
                offerID = nil
            case .failure(let f)?:
                Haptics.warning(); store.show(f.reason, tone: "warn")
            case nil:
                store.show("It could not be bought now.", tone: "warn")
            }
        }
    }

    private func askBuy(_ o: HoldingStakes.Offer, _ q: HoldingStakes.Quote, _ holdingName: String, _ cur: Currency) {
        let name: String = o.name
        let pct: Double = q.percent
        pending = PendingAction(title: "Buy \(holdingPct(pct)) of \(name)?", message: "\(holdingName) pays \(cur.tidyShort(q.price)) from its own account and then owns \(holdingPct(q.heldAfter)): \(q.tierAfter.title.lowercased()).",
                                button: "Buy", amount: q.price, currency: cur) {
            let r: Result<HoldingStakes.Deal, HoldingStakes.Failure>? = store.act { (e: inout GameEngine) -> Result<HoldingStakes.Deal, HoldingStakes.Failure> in
                if let cid = o.companyID { return e.holdingBuyStake(holdingID: holdingID, companyID: cid, percent: pct) }
                return e.holdingBuyRivalStake(holdingID: holdingID, rivalID: o.rivalID ?? 0, percent: pct)
            }
            switch r {
            case .success(let d)?:
                Haptics.success()
                store.show("Bought \(holdingPct(d.percent)) of \(name). The holding now owns \(holdingPct(d.heldAfter)).", tone: "good")
                offerID = nil
            case .failure(let f)?:
                Haptics.warning(); store.show(f.reason, tone: "warn")
            case nil:
                store.show("It could not be bought now.", tone: "warn")
            }
        }
    }
}
