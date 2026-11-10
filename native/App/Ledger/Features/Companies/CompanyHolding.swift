import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

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
        let o = engine.holdingOverview(companyID: company.id).map { (x: HoldingModel.Consolidated) -> HoldingModel.Consolidated in
            var y: HoldingModel.Consolidated = x
            y.subsidiaries = x.subsidiaries.filter { (k: HoldingModel.Subsidiary) -> Bool in !HoldingStakes.isDivision(engine.state.company(k.id) ?? company) }
            return y
        }
        let divisions: [Company] = allDivisions(o)
        let free = engine.companiesForHolding
        let nodes: [StructureNode] = store.memo("structureTree") { (e: GameEngine) -> [StructureNode] in e.structureTree() } ?? []
        let offerIDs: Set<String> = Set(engine.holdingStakeOffers(holdingID: company.id).map { (x: HoldingStakes.Offer) -> String in x.id })
        return VStack(alignment: .leading, spacing: Theme.Space.xl) {
            if let o {
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
            CompanyTeamRoster(engine: engine, company: company)
            if let o {
                MoreBlock(title: "Stakes held", card: false, trailing: { Text("\(o.subsidiaries.count + rivalStakes.count)").textStyle(.caption, tint: Theme.inkFaint) }) {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        if o.subsidiaries.isEmpty && rivalStakes.isEmpty {
                            EmptyState(glyph: Glyph.group, title: "No stakes yet", message: "Put your companies under the holding or buy shares of other companies. Dividends into a holding are taxed far lower.", centered: false)
                        }
                        ForEach(HoldingStakeGroup.allCases) { (g: HoldingStakeGroup) in
                            stakeGroup(g, o, rivalStakes, nodes, offerIDs, cur)
                        }
                    }
                }
                HoldingStartupStakes(engine: engine, company: company)
                if !divisions.isEmpty {
                    MoreBlock(title: "Divisions", card: false, trailing: { Text("\(divisions.count)").textStyle(.caption, tint: Theme.inkFaint) }) {
                        VStack(spacing: 0) {
                            ForEach(Array(divisions.enumerated()), id: \.element.id) { (n: Int, d: Company) in
                                if n > 0 { Hairline().padding(.leading, 40 + Theme.Space.m) }
                                divisionCard(d, cur)
                            }
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
        case .division(let id): HoldingDivisionSheet(holdingID: company.id, companyID: id).environmentObject(store)
        case .talk(let id): HoldingTalkSheet(holdingID: company.id, companyID: id).environmentObject(store)
        case .buy(let offer): HoldingBuyStakes(holdingID: company.id, startOfferID: offer).environmentObject(store)
        }
    }

    private func allDivisions(_ o: HoldingModel.Consolidated?) -> [Company] {
        var out: [Company] = engine.holdingDivisions(hostID: company.id)
        for k in o?.subsidiaries ?? [] { out.append(contentsOf: engine.holdingDivisions(hostID: k.id)) }
        return out
    }

    private func divisionCard(_ d: Company, _ cur: Currency) -> some View {
        let id: Int = d.id
        let hostName: String = HoldingStakes.divisionHostID(d).flatMap { (h: Int) -> String? in engine.state.company(h)?.name } ?? company.name
        return Button { store.openCompany(id) } label: {
            LedgerRow(leading: .thumb(ThumbSpec(kind: .trade, key: d.type, glyph: Glyph.home)), title: d.name, subtitle: "Division of \(hostName)",
                      value: cur.tidyShort(d.cash), valueNote: "cash", chevron: true)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("holding-division-\(id)")
    }

    @ViewBuilder private func stakeGroup(_ g: HoldingStakeGroup, _ o: HoldingModel.Consolidated, _ rivalStakes: [HoldingStakes.RivalStake],
                                         _ nodes: [StructureNode], _ offerIDs: Set<String>, _ cur: Currency) -> some View {
        let subs: [HoldingModel.Subsidiary] = o.subsidiaries.filter { (k: HoldingModel.Subsidiary) -> Bool in HoldingStakeGroup.of(percent: k.ownership) == g }
        let rivals: [HoldingStakes.RivalStake] = rivalStakes.filter { (r: HoldingStakes.RivalStake) -> Bool in HoldingStakeGroup.of(percent: r.percent) == g }
        if !subs.isEmpty || !rivals.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(g.title + " \u{00B7} " + g.range).textStyle(.label, tint: Theme.inkFaint)
                VStack(spacing: 0) {
                    ForEach(Array(subs.enumerated()), id: \.element.id) { (n: Int, k: HoldingModel.Subsidiary) in
                        if n > 0 { Hairline() }
                        heldCard(k, g, cur, nodes, offerIDs)
                    }
                    ForEach(Array(rivals.enumerated()), id: \.element.id) { (n: Int, r: HoldingStakes.RivalStake) in
                        if n > 0 || !subs.isEmpty { Hairline() }
                        rivalCard(r, g, cur, offerIDs)
                    }
                }
            }
        }
    }

    private func heldCard(_ k: HoldingModel.Subsidiary, _ g: HoldingStakeGroup, _ cur: Currency, _ nodes: [StructureNode], _ offerIDs: Set<String>) -> some View {
        let seatedIDs: Set<Int> = Set(engine.holdingSeatedCompanies(holdingID: company.id).map { (c: Company) -> Int in c.id })
        let tax: String = k.inTaxGroup ? " \u{00B7} tax group" : ""
        let line: String = "\(holdingPct((k.ownership * 10).rounded() / 10)) \u{00B7} \(g.word)\(tax)"
        let id: Int = k.id
        let name: String = k.name
        let seat: HoldingStakes.SeatStatus = engine.holdingBoardSeat(holdingID: company.id, companyID: id)
        let seated: Bool = seatedIDs.contains(id)
        let hasDivisions: Bool = !engine.holdingDivisions(hostID: id).isEmpty
        let canMerge: Bool = k.ownership > HoldingStakes.controlAbove && engine.holdingMergeTerms(holdingID: company.id, companyID: id).allowed
        let canBuy: Bool = k.ownership < 99.9 && offerIDs.contains("c:\(id)")
        let node: StructureNode? = nodes.first(where: { (n: StructureNode) -> Bool in n.companyID == id })
        let person: Person? = node?.runnerPersonID.flatMap { (pid: Int) -> Person? in engine.state.people[pid] }
        let primarySeat: Bool = seat.canTake
        let primaryBuy: Bool = !primarySeat && canBuy
        let primaryTitle: String = primarySeat ? "Take a board seat" : (primaryBuy ? "Buy more" : "Open")
        return HoldingStakeRow(tradeKey: k.trade, title: name, subtitle: line, value: cur.tidyShort(k.share), valueNote: "profit " + cur.tidyShort(k.profitTTM),
                               showRunner: true, runnerName: node?.runnerName, runnerRole: person?.role, runnerFace: person?.faceKey, health: node?.health,
                               primary: primaryTitle, key: "held-\(id)",
                               onPrimary: {
                                   if primarySeat { takeSeat(id, name) } else if primaryBuy { stakeSheet = .buy("c:\(id)") } else { store.openCompany(id) }
                               }) {
            if primarySeat || primaryBuy { Button("Open \(name)") { store.openCompany(id) } }
            if canBuy && !primaryBuy { Button("Buy more\u{2026}") { stakeSheet = .buy("c:\(id)") } }
            if seat.hasSeat { Button("Board round and vote\u{2026}") { stakeSheet = .board(id) } }
            if seated { Button("Talk to the people\u{2026}") { stakeSheet = .talk(id) } }
            if seat.hasSeat && seat.reason.isEmpty { Button("Leave the board seat") { leaveSeat(id, name) } }
            Button("Sell some shares\u{2026}") { stakeSheet = .sell(id) }
            if canMerge { Button("Buy out the other owners and merge\u{2026}") { stakeSheet = .merge(id) } }
            if k.ownership >= 99.9 && !hasDivisions { Button("Fold it into the holding as a division\u{2026}") { stakeSheet = .division(id) } }
            if !hasDivisions { Button("Take it back to me\u{2026}", role: .destructive) { askRelease(id, name) } }
        }
    }

    private func rivalCard(_ r: HoldingStakes.RivalStake, _ g: HoldingStakeGroup, _ cur: Currency, _ offerIDs: Set<String>) -> some View {
        let id: Int = r.id
        let canBuy: Bool = offerIDs.contains("r:\(id)")
        return HoldingStakeRow(tradeKey: r.key, title: r.name, subtitle: "\(holdingPct((r.percent * 10).rounded() / 10)) \u{00B7} \(g.word)",
                               value: cur.tidyShort(r.share), valueNote: "paid " + cur.tidyShort(r.paid),
                               showRunner: false, runnerName: nil, runnerRole: nil, runnerFace: nil, health: nil,
                               primary: canBuy ? "Buy more" : "Sell some shares", key: "rival-\(id)",
                               onPrimary: { stakeSheet = canBuy ? HoldingStakeSheet.buy("r:\(id)") : HoldingStakeSheet.sellRival(id) }) {
            if canBuy { Button("Sell some shares\u{2026}") { stakeSheet = .sellRival(id) } }
        }
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
        pending = PendingAction(title: "Take \(name) back to you?", message: "The holding's shares in it come back to you at no price and are owned by you directly again. It drops out of the tax group, and dividends to you are taxed at the normal rate.", button: "Take it back", destructive: true) {
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

struct NewHoldingView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    @State private var name = ""
    @State private var picked: [Int: Double] = [:]
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
                            ForEach(Array(free.enumerated()), id: \.element.id) { (n: Int, c: Company) in
                                if n > 0 { Hairline() }
                                pickRow(c)
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
                        let stakes: [HoldingModel.StakeInput] = free.compactMap { (c: Company) -> HoldingModel.StakeInput? in
                            guard let share = picked[c.id] else { return nil }
                            let pct: Double = share >= 99.9 ? 100 : max(HoldingStakes.minimumPercent, c.ownership * share / 100)
                            return HoldingModel.StakeInput(companyID: c.id, percent: pct)
                        }
                        let r = store.act { $0.createHolding(name: name, stakes: stakes, accountantID: accountantID) }
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

    private func pickRow(_ c: Company) -> some View {
        let on: Bool = picked[c.id] != nil
        let share = Binding<Double>(get: { picked[c.id] ?? 100 }, set: { (v: Double) in picked[c.id] = v })
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Button {
                Haptics.choose()
                if on { picked[c.id] = nil } else { picked[c.id] = 100 }
            } label: {
                HStack {
                    Text(c.name).textStyle(.body, tint: Theme.ink)
                    Spacer()
                    Text("you own \(holdingPct(c.ownership))").textStyle(.caption, tint: Theme.inkFaint)
                    Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Theme.gold : Theme.ivoryFaint)
                }.padding(.vertical, Theme.Space.m).contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityValue(on ? "Selected" : "Not selected")
            .accessibilityIdentifier("new-holding-pick-\(c.id)")
            if on {
                LedgerSlider(value: share, in: 10...100, step: 5, valueText: share.wrappedValue >= 99.9 ? "All of your stake" : "\(Int(share.wrappedValue))% of your stake")
                if share.wrappedValue < 99.9 {
                    let part: Double = c.ownership * share.wrappedValue / 100
                    Text("\(holdingPct((part * 10).rounded() / 10)) of the company goes in; you keep \(holdingPct(((c.ownership - part) * 10).rounded() / 10)).")
                        .textStyle(.caption, tint: Theme.inkFaint)
                }
            }
        }
        .padding(.bottom, on ? Theme.Space.s : 0)
    }
}
