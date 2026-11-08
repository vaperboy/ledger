import SwiftUI
import GameCore
import Countries
import Businesses
import Finance
import Events
import Simulation

/// Commit to a fund: pick the size, read the engine's check (net worth it needs against yours, the most you may commit), then confirm.
struct FundCommitSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var offerID: String
    @State private var multiple = 1
    @State private var pending: PendingAction?

    var body: some View {
        Group {
            if let e = store.engine, let o = e.privateEquityOffersOnTable.first(where: { (x: PrivateEquity.Offer) -> Bool in x.id == offerID }) {
                content(e, o)
            } else {
                Text("This fund is no longer open.").popupText(.body)
            }
        }
        .confirmAction($pending)
        .centerSheetTitle("Commit to a fund")
    }

    private func content(_ e: GameEngine, _ o: PrivateEquity.Offer) -> some View {
        let cur: Currency = e.homeCurrency
        let check: PrivateEquity.CommitCheck = e.fundCommitCheck(offerID: o.id, amount: o.minimum * Double(multiple))
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(o.name).popupText(.figure)
            Text(o.description).popupText(.caption).fixedSize(horizontal: false, vertical: true)
            PopupRow(label: "Manager's record", value: o.trackRecord)
            SegmentedPill(items: [1, 2, 5, 10, 25], title: { (n: Int) -> String in cur.tidyShort(o.minimum * Double(n)) }, selection: $multiple)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                PopupRow(label: "Your commitment", value: cur.tidyShort(check.amount))
                PopupRow(label: "Paid now", value: "Nothing")
                PopupRow(label: "Fund life", value: "10 years")
                PopupRow(label: "Net worth it needs", value: cur.tidyShort(check.requiredNetWorth))
                PopupRow(label: "Your net worth", value: cur.tidyShort(check.netWorth))
                PopupRow(label: "Most you can commit", value: cur.tidyShort(check.largestCommitment))
                Text("The fund calls the money in steps as it invests, charges fees, and pays back as it sells. Most of the return comes late. You can sell your share on the secondary market at a discount.")
                    .popupText(.caption).fixedSize(horizontal: false, vertical: true)
                if check.result == .notRichEnough {
                    Text("Funds take a commitment only from investors worth \(String(format: "%.1f", PrivateEquity.netWorthMultiple)) times that amount. The most you can commit now is \(cur.tidyShort(check.largestCommitment)).")
                        .popupText(.risk).fixedSize(horizontal: false, vertical: true)
                }
                Button("Commit \(cur.tidyShort(check.amount))") { ask(o, check, cur) }.buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .disabled(check.result != .ok)
                    .accessibilityIdentifier("ventures-fund-go")
            }
        }
    }

    private func ask(_ o: PrivateEquity.Offer, _ check: PrivateEquity.CommitCheck, _ cur: Currency) {
        let amount: Double = check.amount
        pending = PendingAction(title: "Commit \(cur.tidyShort(amount)) to \(o.name)?",
                                message: "Nothing leaves your cash today. The fund calls up to \(cur.tidyDisplay(amount)) over the coming years and you cannot withdraw the promise.",
                                button: "Commit", alwaysAsk: true, risk: "Funds can return less than they were paid.", tone: .investment, icon: "chart.pie") {
            switch store.act({ $0.commitToFund(offerID: o.id, amount: amount) }) {
            case .ok?: Haptics.success(); store.show("You committed \(cur.tidyShort(amount)) to \(o.name).", tone: "good"); dismiss()
            case .tooSmall?: store.show("That is below the fund's smallest commitment.", tone: "warn")
            case .notRichEnough?: Haptics.warning(); store.show("Your net worth is too small for that commitment.", tone: "warn")
            default: store.show("That fund is no longer open.", tone: "warn"); dismiss()
            }
        }
    }
}

/// Sell a fund stake on the secondary market. The engine quotes the price; the owner may ask for 0.5 to 1.4 times that, and the buyer takes
/// it, counters, or declines with a reason. Everything the fund still pays out is given up.
struct FundSellSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var fundID: Int
    @State private var multiplier = 1.0
    @State private var reply: VentureSale.Outcome?
    @State private var pending: PendingAction?

    var body: some View {
        Group {
            if let e = store.engine, let f = e.privateEquityFunds.first(where: { (x: PrivateEquity.Fund) -> Bool in x.id == fundID && x.live }) {
                content(e, f)
            } else {
                Text("This fund stake is no longer held.").popupText(.body)
            }
        }
        .confirmAction($pending)
        .centerSheetTitle("Sell a fund stake")
    }

    private func content(_ e: GameEngine, _ f: PrivateEquity.Fund) -> some View {
        let cur: Currency = e.homeCurrency
        let q: VentureSale.Quote = e.fundSecondaryQuote(fundID: f.id)
        let ask: Double = (q.proceeds * multiplier).rounded()
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(f.name).popupText(.figure)
            if q.ok {
                PopupRow(label: "Value of your stake", value: cur.tidyShort(q.fairValue))
                PopupRow(label: "Buyer pays at the quote", value: cur.tidyShort(q.proceeds))
                VenturesAskControl(quote: q, cur: cur, multiplier: $multiplier)
                PopupRow(label: "Against what you paid in", value: (ask + f.distributed >= q.costBasis ? "+" : "\u{2212}") + cur.tidyShort(abs(ask + f.distributed - q.costBasis)))
                Text("Secondary buyers pay \(Int(((1 - q.factor) * 100).rounded()))% under the fund's value. You give up everything it still pays out, and the gain is taxed.")
                    .popupText(.caption).fixedSize(horizontal: false, vertical: true)
                VenturesSaleReply(reply: reply, cur: cur) { (c: Double) in sell(cur, multiplier: c / max(1, q.proceeds)) }
                Button("Ask \(cur.tidyShort(ask))") { askConfirm(f, ask, cur) }.buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .accessibilityIdentifier("ventures-fund-sell-go")
            } else {
                Text(q.reason).popupText(.risk).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func askConfirm(_ f: PrivateEquity.Fund, _ ask: Double, _ cur: Currency) {
        let m: Double = multiplier
        pending = PendingAction(title: "Sell \(f.name)?",
                                message: "You ask \(cur.tidyShort(ask)). The buyer may take it, offer less, or refuse. A sale cannot be undone.",
                                button: "Sell", destructive: true, tone: .investment, icon: "arrow.up.right") {
            sell(cur, multiplier: m)
        }
    }

    private func sell(_ cur: Currency, multiplier m: Double) {
        let id: Int = fundID
        let out: VentureSale.Outcome? = store.act { (e: inout GameEngine) -> VentureSale.Outcome? in
            e.sellFundStake(fundID: id, askingMultiplier: m)
        } ?? nil
        if case .sold(let v)? = out {
            Haptics.success(); store.show("Sold for \(cur.tidyShort(v)).", tone: "good"); dismiss()
        } else {
            Haptics.warning(); reply = out ?? .unavailable("That fund could not be sold.")
        }
    }
}
