import SwiftUI
import GameCore
import Countries
import Businesses
import Finance
import Events
import Simulation

struct VenturesGroupsSection: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @Binding var open: String?
    @Binding var sheet: VentureSheet?
    @Binding var pending: PendingAction?

    var body: some View {
        let cur: Currency = engine.homeCurrency
        let big: [BigMeeting.Stake] = engine.bigMeetingStakes
        let groups: [GroupDeals.Stake] = engine.groupStakes
        let offer: BigMeeting.Offer? = engine.bigMeetingOffer
        return LedgerSection("Group stakes") {
            VStack(alignment: .leading, spacing: 0) {
                if let o = offer { offerBlock(o, cur) }
                ForEach(Array(big.enumerated()), id: \.element.id) { item in
                    if item.offset > 0 || offer != nil { Hairline() }
                    LedgerRow(title: item.element.name,
                              subtitle: "\(Int(item.element.pct))% \u{00B7} \(cur.tidyShort(item.element.yearlyProfitShare)) a year profit share",
                              value: cur.tidyShort(item.element.value))
                }
                ForEach(Array(groups.enumerated()), id: \.element.id) { item in
                    let s: GroupDeals.Stake = item.element
                    let gain: Double = s.value - s.cost
                    if item.offset > 0 || offer != nil || !big.isEmpty { Hairline() }
                    LedgerRow(title: s.name,
                              subtitle: "\(Int(saturating: (s.ownership * 100).rounded()))% since \(GameCalendar.dateString(week: s.sinceWeek))",
                              value: cur.tidyShort(s.value),
                              valueNote: (gain >= 0 ? "+" : "\u{2212}") + cur.tidyShort(abs(gain)) + " on cost", valueNoteTint: Theme.change(gain))
                }
            }
        }
    }

    private func offerBlock(_ o: BigMeeting.Offer, _ cur: Currency) -> some View {
        let key: String = "g\(o.id)"
        let isOpen: Bool = open == key
        let fin = engine.bigMeetingFinancing(price: o.price)
        let weeksLeft: Int = max(0, o.expiresWeek - engine.state.week)
        return VStack(alignment: .leading, spacing: 0) {
            LedgerRow(title: "\(o.pct)% of \(o.target)",
                      subtitle: "From \(o.seller), \(o.sellerCompany) \u{00B7} \(weeksLeft.weeksText) left",
                      value: cur.tidyShort(o.price),
                      pill: "Offer", pillTone: .good,
                      chevron: false, identifier: "ventures-group-offer") { open = isOpen ? nil : key }
            if isOpen {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    FigureCard(items: [
                        .init(label: "Price", value: cur.tidyShort(o.price)),
                        .init(label: "You pay", value: cur.tidyShort(fin.own), sub: "from your cash"),
                        .init(label: "Bank lends", value: cur.tidyShort(fin.borrow), sub: "over 10 years"),
                    ])
                    Text("Pays about \(cur.tidyShort(o.yearlyProfitShare)) a year in profit share; its value moves with the market.").textStyle(.caption, tint: Theme.inkFaint)
                    if engine.bigMeetingRatesWarning() {
                        Text("If rates rise two points the loan interest would cost more than the profit share.").textStyle(.caption, tint: Theme.warn)
                    }
                    WrapRow {
                        Group {
                            Button("Buy for \(cur.tidyShort(fin.own)) of your cash") { askBuy(o, fin.own, cur) }.buttonStyle(PrimaryButtonStyle(size: .compact))
                            Button("Ask for 10% off") { counter() }.buttonStyle(SecondaryButtonStyle(size: .compact)).disabled(o.countered)
                            Button("Walk away") { askWalk(o) }.buttonStyle(TertiaryButtonStyle(size: .compact))
                        }
                    }
                }
                .padding(.bottom, Theme.Space.m)
            }
        }
    }

    private func askBuy(_ o: BigMeeting.Offer, _ own: Double, _ cur: Currency) {
        pending = PendingAction(title: "Buy \(o.pct)% of \(o.target)?",
                                message: "The price is \(cur.tidyShort(o.price)): \(cur.tidyShort(own)) from your cash and the rest borrowed from the bank over ten years.",
                                button: "Buy", amount: own, currency: cur, risk: "The loan stays even if the stake loses value.", tone: .investment, icon: "chart.pie") {
            switch store.act({ $0.acceptBigMeetingOffer() }) {
            case .ok?: Haptics.success(); store.show("You bought \(o.pct)% of \(o.target).", tone: "good")
            case .needsOwnMoney(let need)?: Haptics.warning(); store.show("You need \(cur.tidyShort(need)) in cash.", tone: "warn")
            default: store.show("The offer has gone.", tone: "warn")
            }
        }
    }

    private func counter() {
        switch store.act({ $0.counterBigMeetingOffer() }) {
        case .some(.some(true)): store.show("They agreed to 10% off.", tone: "good")
        case .some(.some(false)): store.show("They walked away from the deal.", tone: "warn")
        default: store.show("You already asked, or the offer has gone.", tone: "n")
        }
    }

    private func askWalk(_ o: BigMeeting.Offer) {
        pending = PendingAction(title: "Walk away from \(o.target)?", message: "The offer is withdrawn and will not come back.", button: "Walk away", destructive: true, tone: .danger, icon: "xmark") {
            store.settle(store.act { $0.walkAwayFromBigMeeting() }, "You walked away.", same: "The offer had already gone.")
        }
    }
}
