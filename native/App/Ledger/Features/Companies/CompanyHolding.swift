import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// A holding company's own section: what it is worth, the companies under it, the index fund, and moving money.
struct CompanyHolding: View {
    private func figureItems(_ o: HoldingModel.Consolidated, _ cur: Currency) -> [KeyFigures.Item] {
        return [
            .init(label: "Companies", value: cur.tidyShort(o.companiesValue), sub: "your share"),
            .init(label: "Index fund", value: cur.tidyShort(o.indexFund)),
            .init(label: "Revenue 12 mo", value: cur.tidyShort(o.revenueTTM), sub: "your share"),
            .init(label: "Cash in group", value: cur.tidyShort(o.cashInGroup)),
        ]
    }

    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var amount = 0.0
    @State private var pending: PendingAction?
    @State private var showBuy = false
    @State private var showMove = false
    @State private var stakeSheet: HoldingStakeSheet?

    var body: some View {
        let cur = engine.currency(for: company)
        let rivalStakes: [HoldingStakes.RivalStake] = engine.holdingRivalStakes(holdingID: company.id)
        let o = engine.holdingOverview(companyID: company.id)
        let free = engine.companiesForHolding
        return VStack(alignment: .leading, spacing: Theme.Space.xl) {
            if let o {
                // The holding's value is the hero; the consolidated figures follow in one strip.
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text("Holding value").textStyle(.label, tint: Theme.inkFaint)
                    Text(cur.tidyShort(o.holdingValue)).textStyle(.display).lineLimit(1).minimumScaleFactor(0.6)
                    Text("Profit \(cur.tidyShort(o.profitTTM)) over 12 months, your share").textStyle(.caption, tint: o.profitTTM < 0 ? Theme.loss : Theme.inkSoft).lineLimit(2)
                }
                .accessibilityElement(children: .combine)
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    FigureRow(items: figureItems(o, cur), columns: 2, combineCells: true)
                    if o.groupCovered > 0 {
                        Text("Tax group: profits cover \(cur.tidyShort(o.groupCovered)) of sister companies' losses this year.").textStyle(.caption, tint: Theme.gain)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            // The holding's own management (its managing director): the holding has no staff list, so its roster lives here.
            CompanyTeamRoster(engine: engine, company: company)
            if let o {
                MoreBlock(title: "Stakes held", card: false, trailing: { Text("\(o.subsidiaries.count + rivalStakes.count)").textStyle(.caption, tint: Theme.inkFaint) }) {
                    VStack(spacing: 0) {
                        if o.subsidiaries.isEmpty && rivalStakes.isEmpty {
                            EmptyState(glyph: Glyph.group, title: "No stakes yet", message: "Put your companies under the holding or buy shares of other companies. Dividends into a holding are taxed far lower.", centered: false)
                        }
                        ForEach(Array(o.subsidiaries.enumerated()), id: \.element.id) { (n: Int, k: HoldingModel.Subsidiary) in
                            if n > 0 { Hairline().padding(.leading, 40 + Theme.Space.m) }
                            heldCard(k, cur)
                        }
                        ForEach(Array(rivalStakes.enumerated()), id: \.element.id) { (n: Int, r: HoldingStakes.RivalStake) in
                            if n > 0 || !o.subsidiaries.isEmpty { Hairline().padding(.leading, 40 + Theme.Space.m) }
                            rivalCard(r, cur)
                        }
                    }
                }
                HStack(spacing: Theme.Space.s) {
                    Button("Buy stakes") { Haptics.tap(); showBuy = true }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: true)).accessibilityIdentifier("holding-buy-stakes")
                    if !free.isEmpty {
                        Button("Put companies under it") { Haptics.tap(); showMove = true }
                            .buttonStyle(SecondaryButtonStyle(fullWidth: true)).accessibilityIdentifier("holding-put-under")
                    }
                }
                HoldingFinanceManagerCard(engine: engine, company: company)
                MoreBlock("Move money") {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        AmountField(title: "Amount", currency: cur, amount: $amount)
                        Button("Put money in") {
                            if amount > 0, store.act({ $0.putMoneyInto(companyID: company.id, amount: amount) }) == true { Haptics.success(); store.show("Moved in.", tone: "good") }
                            else { Haptics.warning(); store.show(amount > 0 ? "You don't have that much available." : "Enter an amount first.", tone: "warn") }
                        }.buttonStyle(PrimaryButtonStyle(fullWidth: true))
                        Text("Dividends flow up from the companies into the holding, and down to you. A holding that runs short of cash takes a dividend from a company by itself.")
                            .textStyle(.caption, tint: Theme.inkFaint)
                    }
                }
            } else {
                Text("This holding company has no figures yet.").textStyle(.caption, tint: Theme.inkFaint)
            }
        }
        // The holding's blocks sit on the page with no surface of their own.
        .environment(\.insideCard, true)
        .confirmAction($pending)
        .centerSheet(isPresented: $showBuy, size: .tall, category: .detail, tone: .info) { HoldingBuyStakes(holdingID: company.id).environmentObject(store) }
        .centerSheet(isPresented: $showMove, size: .tall, category: .detail, tone: .info) { HoldingMoveSheet(holdingID: company.id).environmentObject(store) }
        .centerSheet(item: $stakeSheet, category: .detail, tone: .info) { (sh: HoldingStakeSheet) in stakeContent(sh) }
    }

    @ViewBuilder private func stakeContent(_ sh: HoldingStakeSheet) -> some View {
        switch sh {
        case .sell(let id): HoldingSellSheet(holdingID: company.id, companyID: id, rivalID: nil).environmentObject(store)
        case .sellRival(let id): HoldingSellSheet(holdingID: company.id, companyID: nil, rivalID: id).environmentObject(store)
        case .board(let id): HoldingBoardSheet(holdingID: company.id, companyID: id).environmentObject(store)
        case .merge(let id): HoldingMergeSheet(holdingID: company.id, companyID: id).environmentObject(store)
        }
    }

    /// One stake in a company: tier and percent under the name, its share of the value at the right; the row's menu holds what can be done with it.
    private func heldCard(_ k: HoldingModel.Subsidiary, _ cur: Currency) -> some View {
        let tier: HoldingStakes.Tier = HoldingStakes.tier(forPercent: k.ownership)
        let tax: String = k.inTaxGroup ? " \u{00B7} tax group" : ""
        let line: String = "\(holdingPct((k.ownership * 10).rounded() / 10)) \u{00B7} \(tier.title)\(tax)"
        let id: Int = k.id
        let name: String = k.name
        let seat: HoldingStakes.SeatStatus = engine.holdingBoardSeat(holdingID: company.id, companyID: id)
        let canMerge: Bool = k.ownership > HoldingStakes.controlAbove && engine.holdingMergeTerms(holdingID: company.id, companyID: id).allowed
        return Menu {
            Button("Open \(name)") { store.openCompany(id) }
            if seat.hasSeat { Button("Board round and vote\u{2026}") { stakeSheet = .board(id) } }
            if seat.canTake { Button("Take a board seat") { takeSeat(id, name) } }
            if seat.hasSeat && seat.reason.isEmpty { Button("Leave the board seat") { leaveSeat(id, name) } }
            Button("Sell part\u{2026}") { stakeSheet = .sell(id) }
            if canMerge { Button("Merge into the holding\u{2026}") { stakeSheet = .merge(id) } }
            Button("Release to me\u{2026}", role: .destructive) { askRelease(id, name) }
        } label: {
            LedgerRow(leading: .thumb(ThumbSpec(kind: .trade, key: k.trade, glyph: Glyph.home)), title: name, subtitle: line,
                      value: cur.tidyShort(k.share), valueNote: "profit " + cur.tidyShort(k.profitTTM), chevron: true)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("holding-held-\(id)")
    }

    /// A stake in another business: its share of the value, with sale as the only action.
    private func rivalCard(_ r: HoldingStakes.RivalStake, _ cur: Currency) -> some View {
        let id: Int = r.id
        return Menu {
            Button("Sell part\u{2026}") { stakeSheet = .sellRival(id) }
        } label: {
            LedgerRow(leading: .thumb(ThumbSpec(kind: .trade, key: r.key, glyph: Glyph.home)), title: r.name,
                      subtitle: "\(holdingPct((r.percent * 10).rounded() / 10)) \u{00B7} \(r.tier.title)", value: cur.tidyShort(r.share), valueNote: "paid " + cur.tidyShort(r.paid), chevron: true)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("holding-rival-\(id)")
    }

    private func takeSeat(_ id: Int, _ name: String) {
        let r: Result<Void, HoldingStakes.Failure>? = store.act { (e: inout GameEngine) -> Result<Void, HoldingStakes.Failure> in e.holdingTakeBoardSeat(holdingID: company.id, companyID: id) }
        if case .failure(let f)? = r { Haptics.warning(); store.show(f.reason, tone: "warn") } else { Haptics.success(); store.show("The holding now has a seat on the board of \(name).", tone: "good") }
    }

    private func leaveSeat(_ id: Int, _ name: String) {
        let r: Result<Void, HoldingStakes.Failure>? = store.act { (e: inout GameEngine) -> Result<Void, HoldingStakes.Failure> in e.holdingLeaveBoardSeat(holdingID: company.id, companyID: id) }
        if case .failure(let f)? = r { Haptics.warning(); store.show(f.reason, tone: "warn") } else { Haptics.choose(); store.show("The holding left the board of \(name).", tone: "n") }
    }

    private func askRelease(_ id: Int, _ name: String) {
        pending = PendingAction(title: "Release \(name)?", message: "The holding's shares in it come back to you at no price and are owned by you directly again. It drops out of the tax group, and dividends to you are taxed at the normal rate.", button: "Release", destructive: true) {
            // Shares moved under the holding and shares it bought are released separately; either counts.
            let ok: Bool = store.act { (e: inout GameEngine) -> Bool in
                let moved: Bool = e.state.company(id)?.holdingID == company.id && e.releaseFromHolding(companyID: id)
                let bought: Bool = e.holdingReleaseStake(holdingID: company.id, companyID: id)
                return moved || bought
            } ?? false
            Haptics.choose()
            store.show(ok ? "\(name) is owned by you directly again." : "It could not be released now.", tone: ok ? "good" : "warn")
        }
    }
}

/// Register a new holding company and choose which companies it holds.
struct NewHoldingView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    @State private var name = ""
    @State private var picked: Set<Int> = []
    @State private var accountantID: Int?

    var body: some View {
        if let e = store.engine {
            let country = e.homeCountry
            let cur = e.homeCurrency
            let free = e.companiesForHolding
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    ZStack(alignment: .topTrailing) {
                        MoreHeader(glyph: Glyph.group, title: "A holding company", blurb: "Owns the shares of your other limited companies and collects their dividends in one place. Tap (i) for how it is taxed.")
                        HoldingInfoButton()
                    }
                    MoreBlock("Name") {
                        TextField("Holding company name", text: $name).textFieldStyle(.plain).font(.system(size: 16)).foregroundStyle(Theme.ivory)
                    }
                    MoreBlock("Which companies it holds") {
                        VStack(spacing: 0) {
                            if free.isEmpty { Text("No limited companies to hold yet. You can add them later.").textStyle(.caption, tint: Theme.inkFaint) }
                            ForEach(Array(free.enumerated()), id: \.element.id) { n, c in
                                if n > 0 { Hairline() }
                                Button {
                                    if picked.contains(c.id) { picked.remove(c.id) } else { picked.insert(c.id) }
                                    Haptics.choose()
                                } label: {
                                    HStack {
                                        Text(c.name).textStyle(.body, tint: Theme.ink)
                                        Spacer()
                                        Image(systemName: picked.contains(c.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(picked.contains(c.id) ? Theme.gold : Theme.ivoryFaint)
                                    }.padding(.vertical, Theme.Space.m).contentShape(Rectangle())
                                }.buttonStyle(PressableStyle()).accessibilityValue(picked.contains(c.id) ? "Selected" : "Not selected")
                            }
                        }
                    }
                    AccountantStep(countryCode: e.state.homeCountryCode, currency: cur, accountantID: $accountantID)
                    MoreBlock("What it costs") {
                        VStack(spacing: 0) {
                            FlatRow(label: "Share capital", value: cur.tidyShort(country.shareCapitalMinimum), sub: "stays in the holding", rule: false)
                            FlatRow(label: "Registration", value: cur.tidyShort(country.registrationFee))
                        }
                    }
                    HStack { Button("Create the holding company") {
                        let r = store.act { $0.createHolding(name: name, companies: Array(picked), accountantID: accountantID) }
                        switch r {
                        case .success(let id)?: Haptics.success(); store.show("Registered.", tone: "good"); store.openCompany(id)
                        case .failure(.notEnoughCash)?: Haptics.warning(); store.show("You need \(cur.tidyShort(country.shareCapitalMinimum + country.registrationFee)) in your account.", tone: "warn")
                        default: store.show("Not possible.", tone: "warn")
                        }
                    }.buttonStyle(TinyButtonStyle()); Spacer() }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.page)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .appScreen(title: "New holding company", subtitle: "Register it and choose what it holds.")
        }
    }
}
