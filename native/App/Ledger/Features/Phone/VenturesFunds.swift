import SwiftUI
import GameCore
import Countries
import Businesses
import Finance
import Events
import Simulation

/// Funds: the private equity funds you committed to (value, multiple, what is still to be called, sell on the secondary market) and the funds
/// open to commitments this year. An open fund opens `FundCommitSheet`.
struct VenturesFundsSection: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @Binding var open: String?
    @Binding var sheet: VentureSheet?
    @Binding var pending: PendingAction?

    var body: some View {
        let cur: Currency = engine.homeCurrency
        let funds: [PrivateEquity.Fund] = engine.privateEquityFunds
        let offers: [PrivateEquity.Offer] = engine.privateEquityOffersOnTable
        let liveCount: Int = funds.filter { (f: PrivateEquity.Fund) -> Bool in f.live }.count
        return LedgerSection(title: "Funds", trailing: { if liveCount > 0 { Text("\(liveCount) held").textStyle(.caption, tint: Theme.inkFaint) } }) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(funds.enumerated()), id: \.element.id) { item in
                    if item.offset > 0 { Hairline() }
                    fundRow(item.element, cur)
                }
                Text("Open to commitments this year").capsLabel(Theme.inkFaint).padding(.top, funds.isEmpty ? 0 : Theme.Space.m).padding(.bottom, Theme.Space.xs)
                if offers.isEmpty {
                    EmptyState(glyph: Glyph.ventures, title: "No fund is open", message: "A new set of funds opens every calendar year.", centered: false)
                        .padding(.vertical, Theme.Space.s)
                }
                ForEach(Array(offers.enumerated()), id: \.element.id) { item in
                    if item.offset > 0 { Hairline() }
                    offerRow(item.element, cur)
                }
            }
        }
    }

    private func offerRow(_ o: PrivateEquity.Offer, _ cur: Currency) -> some View {
        LedgerRow(title: o.name,
                  subtitle: "\(PrivateEquity.styles[o.style]?.name ?? o.style) \u{00B7} \(o.trackRecord)",
                  value: cur.tidyShort(o.minimum), valueNote: "smallest commitment",
                  pill: "Commit", pillTone: .good,
                  identifier: "ventures-fund-offer-\(o.id)") { sheet = .fund(o.id) }
    }

    private func fundRow(_ f: PrivateEquity.Fund, _ cur: Currency) -> some View {
        let year: Int = (engine.state.week - f.startWeek) / 52 + 1
        let multiple: Double = f.live ? f.multiple : f.finalMultiple
        let key: String = "f\(f.id)"
        let isOpen: Bool = open == key
        let toggle: (() -> Void)? = f.live ? { open = isOpen ? nil : key } : nil
        return VStack(alignment: .leading, spacing: 0) {
            LedgerRow(title: f.name,
                      subtitle: "\(PrivateEquity.styles[f.style]?.name ?? f.style) \u{00B7} " + (f.live ? "year \(year) of 10" : f.sold ? "sold" : "wound up"),
                      value: f.live ? cur.tidyShort(f.nav) : cur.tidyShort(f.distributed),
                      valueNote: String(format: "%.2f\u{00D7}", multiple), valueNoteTint: Theme.change(multiple - 1),
                      chevron: false, identifier: "ventures-fund-\(f.id)", action: toggle)
            if f.live && isOpen {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    FigureCard(items: [
                        .init(label: "Committed", value: cur.tidyShort(f.committed), sub: f.toBeCalled > 0 ? "\(cur.tidyShort(f.toBeCalled)) still to call" : "all called"),
                        .init(label: "Value now", value: cur.tidyShort(f.nav)),
                        .init(label: "Paid back", value: cur.tidyShort(f.distributed)),
                    ])
                    Button("Sell on the secondary market") { askSell(f, cur) }.buttonStyle(SecondaryButtonStyle(size: .compact))
                }
                .padding(.bottom, Theme.Space.m)
            }
        }
    }

    private func askSell(_ f: PrivateEquity.Fund, _ cur: Currency) {
        let price: Double = engine.secondaryPrice(fundID: f.id)
        let off: Int = Int((engine.secondaryDiscount(fundID: f.id) * 100).rounded())
        pending = PendingAction(title: "Sell \(f.name)?",
                                message: "A buyer pays \(cur.tidyShort(price)) now, \(off)% under the fund's value. You give up everything it still pays out, and the gain is taxed. It cannot be undone.",
                                button: "Sell for \(cur.tidyShort(price))", destructive: true, tone: .investment, icon: "arrow.up.right") {
            let got: Double? = store.act { $0.sellFundStake(fundID: f.id) } ?? nil
            if let got { Haptics.success(); store.show("Sold for \(cur.tidyShort(got)).", tone: "good") } else { store.show("That fund could not be sold.", tone: "warn") }
        }
    }
}

/// Commit to a fund: pick the size, read what it asks of you (nothing now, money called over the years, net worth it needs), then confirm.
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
        let amount: Double = o.minimum * Double(multiple)
        let need: Double = amount * 1.5
        let worth: Double = e.netWorth.total
        let rich: Bool = worth >= need
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(o.name).popupText(.figure)
            Text(o.description).popupText(.caption).fixedSize(horizontal: false, vertical: true)
            PopupRow(label: "Manager's record", value: o.trackRecord)
            SegmentedPill(items: [1, 2, 5, 10, 25], title: { (n: Int) -> String in cur.tidyShort(o.minimum * Double(n)) }, selection: $multiple)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                PopupRow(label: "Your commitment", value: cur.tidyShort(amount))
                PopupRow(label: "Paid now", value: "Nothing")
                PopupRow(label: "Fund life", value: "10 years")
                PopupRow(label: "Net worth it needs", value: cur.tidyShort(need))
                PopupRow(label: "Your net worth", value: cur.tidyShort(worth))
                Text("The fund calls the money in steps as it invests, charges fees, and pays back as it sells. Most of the return comes late. You can sell your share on the secondary market at a discount.")
                    .popupText(.caption).fixedSize(horizontal: false, vertical: true)
                if !rich { Text("Funds only take a commitment up to two thirds of your net worth.").popupText(.risk) }
                Button("Commit \(cur.tidyShort(amount))") { ask(o, amount, cur) }.buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .disabled(!rich)
                    .accessibilityIdentifier("ventures-fund-go")
            }
        }
    }

    private func ask(_ o: PrivateEquity.Offer, _ amount: Double, _ cur: Currency) {
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

// MARK: Group stakes

/// Stakes in groups: the offer on the table from the big meeting (buy, ask for 10% off, walk away) and the stakes you hold.
struct VenturesGroupsSection: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @Binding var open: String?
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
                              subtitle: "\(Int((s.ownership * 100).rounded()))% since \(GameCalendar.dateString(week: s.sinceWeek))",
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
