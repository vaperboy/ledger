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
        let targets: [RivalGroups.Group] = engine.rivalGroupsAround().filter { (g: RivalGroups.Group) -> Bool in !g.gone }
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
                if !targets.isEmpty {
                    Text("Bid for a share of a group").capsLabel(Theme.inkFaint)
                        .padding(.top, (offer != nil || !big.isEmpty || !groups.isEmpty) ? Theme.Space.m : 0).padding(.bottom, Theme.Space.xs)
                    ForEach(Array(targets.enumerated()), id: \.element.id) { item in
                        if item.offset > 0 { Hairline() }
                        targetRow(item.element, cur)
                    }
                }
            }
        }
    }

    private func targetRow(_ g: RivalGroups.Group, _ cur: Currency) -> some View {
        let worth: Double = engine.groupStakeQuote(groupID: g.id, fraction: 0.1, multiplier: 1, chance: 1).groupValue
        return LedgerRow(title: g.name,
                         subtitle: "\(g.strategyName) \u{00B7} \(g.owner) \u{00B7} \(g.branches) branches",
                         value: worth > 0 ? cur.tidyShort(worth) : "No value",
                         valueNote: worth > 0 ? "worth in all" : "",
                         pill: "Bid", pillTone: .good,
                         identifier: "ventures-group-\(g.id)") { sheet = .groupBuy(g.id) }
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

struct GroupStakeSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var groupID: String
    @State private var fraction = 0.1
    @State private var multiplier = 1.0
    @State private var pending: PendingAction?
    @State private var failure: GroupDeals.StakeFailure?

    private var chance: Double { min(0.95, max(0.1, 0.5 + (multiplier - 1))) }

    var body: some View {
        Group {
            if let e = store.engine, let g = e.rivalGroupsAround().first(where: { (x: RivalGroups.Group) -> Bool in x.id == groupID && !x.gone }) {
                content(e, g)
            } else {
                Text("This group is no longer available.").popupText(.body)
            }
        }
        .confirmAction($pending)
        .centerSheetTitle("Buy into a group")
    }

    private func content(_ e: GameEngine, _ g: RivalGroups.Group) -> some View {
        let cur: Currency = e.homeCurrency
        let shownMultiplier = Binding<Double>(get: { (multiplier * 100).rounded() / 100 }, set: { (v: Double) in multiplier = v; failure = nil })
        let q: GroupDeals.StakeQuote = e.groupStakeQuote(groupID: g.id, fraction: fraction, multiplier: multiplier, chance: chance)
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(g.name).popupText(.figure)
            Text("\(g.strategyName). \(g.strategyText)").popupText(.caption).fixedSize(horizontal: false, vertical: true)
            PopupRow(label: "Worth in all", value: cur.tidyShort(q.groupValue))
            SegmentedPill(items: [0.05, 0.1, 0.2, 0.33, 0.5], title: { (f: Double) -> String in "\(Int(saturating: (f * 100).rounded()))%" }, selection: $fraction)
            LedgerSlider(value: shownMultiplier, in: 0.5...3, step: 0.05, valueText: String(format: "Bid %.2f\u{00D7} fair value", multiplier))
                .accessibilityIdentifier("ventures-group-bid")
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                PopupRow(label: "Fair value of the share", value: cur.tidyShort(q.groupValue * fraction))
                PopupRow(label: "You pay if you win", value: cur.tidyShort(q.price))
                PopupRow(label: "Chance of winning", value: "\(Int(saturating: (chance * 100).rounded()))%")
                PopupRow(label: "Your cash", value: cur.tidyShort(q.available))
                Text("Other bidders may win instead; then nothing is paid. A bigger bid wins more often. The stake's value follows the group's profit and debt.")
                    .popupText(.caption).fixedSize(horizontal: false, vertical: true)
                if let why = q.refusal {
                    Text(why.reason).popupText(.risk).fixedSize(horizontal: false, vertical: true)
                } else if !q.canAfford {
                    Text("You need \(cur.tidyShort(q.price - q.available)) more in cash to win this.").popupText(.risk)
                }
                if let f = failure { Text(f.reason).popupText(.risk).fixedSize(horizontal: false, vertical: true) }
                Button("Bid \(cur.tidyShort(q.price)) for \(Int(saturating: (fraction * 100).rounded()))%") { ask(g, q, cur) }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .disabled(q.refusal != nil || !q.canAfford)
                    .accessibilityIdentifier("ventures-group-bid-go")
            }
        }
    }

    private func ask(_ g: RivalGroups.Group, _ q: GroupDeals.StakeQuote, _ cur: Currency) {
        let f: Double = fraction, m: Double = multiplier, c: Double = chance
        let id: String = g.id
        pending = PendingAction(title: "Bid for \(Int(saturating: (f * 100).rounded()))% of \(g.name)?",
                                message: "If you win, \(cur.tidyDisplay(q.price)) leaves your cash now. You win with a \(Int(saturating: (c * 100).rounded()))% chance; if another bidder wins, nothing is paid.",
                                button: "Bid", amount: q.price, currency: cur,
                                risk: "The stake can lose value if the group's profit falls or its debt grows.", tone: .investment, icon: "chart.pie") {
            let r: Result<Double, GroupDeals.StakeFailure> = store.act { (e: inout GameEngine) -> Result<Double, GroupDeals.StakeFailure> in
                e.buyGroupStake(groupID: id, fraction: f, multiplier: m, chance: c)
            } ?? .failure(.noGroup)
            switch r {
            case .success(let paid): Haptics.success(); store.show("You bought \(Int(saturating: (f * 100).rounded()))% of \(g.name) for \(cur.tidyShort(paid)).", tone: "good"); dismiss()
            case .failure(let why): Haptics.warning(); failure = why; store.show(why.reason, tone: "warn")
            }
        }
    }
}
