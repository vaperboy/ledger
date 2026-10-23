import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// One chain as a whole: what needs you, how the stores compare (each opens its company), who manages the chain and each city,
/// the rules every store follows, its board, franchising, supply between your companies and growth. Opened from the Group tab and
/// from a store's Chain section. Store-level work (staff, prices, stock) stays in each store; logic is in `Chains`, `ManagerModel`.
struct ChainView: View {
    @EnvironmentObject var store: GameStore
    var chainID: Int
    @State private var pending: PendingAction?
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        if let e = store.engine, let sum = e.chainSummary(id: chainID), let first = sum.stores.first.flatMap({ e.state.company($0.id) }) {
            let cur = e.currency(for: first)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    header(e, sum)
                    ChainFigures(summary: sum, currency: cur)
                    ChainAttention(engine: e, summary: sum, currency: cur, pending: $pending)
                    ChainStoreComparison(engine: e, summary: sum, currency: cur)
                    ChainStaffShortages(engine: e, chainID: sum.id)
                    ExecutivePosts(engine: e, chainID: sum.id)
                    ChainRulesSection(engine: e, chainID: sum.id)
                    boardLink(e, sum)
                    if let fid = sum.franchisingCompanyID, let fco = e.state.company(fid) { FranchisorCard(engine: e, company: fco) }
                    ChainSupplyOverview(engine: e, summary: sum, currency: cur)
                    ChainNewStore(engine: e, summary: sum, currency: cur)
                    ChainJoin(engine: e, summary: sum)
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 1100).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .ledgerBackground()
            .navigationTitle(sum.name)
            .navigationBarTitleDisplayMode(.inline)
            .confirmAction($pending)
            .alert("Rename the chain", isPresented: $renaming) {
                TextField("New name", text: $newName)
                Button("Rename") { rename(sum, cur) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every store takes the new name and pays for its own new signs (about \(cur.tidyShort(cur.scaledPrice(40000))) for a standard store). Awareness of the old name is not carried over in full.")
            }
        } else {
            Text("This chain no longer exists.").foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    private func header(_ e: GameEngine, _ sum: Chains.Summary) -> some View {
        let cities = Set(sum.stores.map { $0.cityName }).count
        return VStack(alignment: .leading, spacing: 4) {
            Text(sum.name).font(.serifTitle(26)).foregroundStyle(Theme.ivory).lineLimit(2).minimumScaleFactor(0.7)
            HStack {
                Text("\(e.data.catalog[sum.tradeID]?.name ?? "Chain") · \(sum.stores.count) \(sum.stores.count == 1 ? "store" : "stores") in \(cities) \(cities == 1 ? "city" : "cities")")
                    .font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).lineLimit(1)
                Spacer()
                Button("Rename") { newName = sum.name; renaming = true }.font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.gold).buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func boardLink(_ e: GameEngine, _ sum: Chains.Summary) -> some View {
        let key = "ch:\(sum.id)"
        if e.boardIsActive(key: key) {
            LedgerSection("Board") {
                NavigationLink { BoardView(key: key) } label: { BoardLinkRow(engine: e, key: key) }.buttonStyle(.plain)
            }
        }
    }

    private func rename(_ sum: Chains.Summary, _ cur: Currency) {
        let name = newName
        switch store.act({ $0.renameChain(chainID: sum.id, to: name) }) {
        case .ok?: Haptics.success(); store.show("The chain is now called \(name.trimmingCharacters(in: .whitespaces)).", tone: "good")
        case .tooShort?: store.show("Choose a different name of at least two letters.", tone: "warn")
        case .nameTaken?: store.show("Another of your chains has that name.", tone: "warn")
        case .notEnoughCash?: Haptics.warning(); store.show("A store does not have the cash for new signs.", tone: "warn")
        default: store.show("The chain could not be renamed.", tone: "warn")
        }
    }
}

/// The chain's figures in one block.
struct ChainFigures: View {
    var summary: Chains.Summary
    var currency: Currency

    var body: some View {
        let r = summary.reach
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            KeyFigures(items: [
                .init(label: "Revenue / mo", value: currency.tidyShort(summary.revenue)),
                .init(label: "Profit / mo", value: currency.tidyShort(summary.profit), tint: summary.profit < 0 ? Theme.loss : Theme.ivory),
                .init(label: "Staff", value: "\(summary.staff)"),
                .init(label: "Reach", value: r.label, sub: "\(r.outlets) outlets"),
                .init(label: "Buying discount", value: String(format: "%.1f%%", r.rebate * 100), sub: "of cost of sales"),
                .init(label: "Franchise units", value: "\(summary.franchiseUnits)"),
            ])
            RateBar(label: "Name known by", fraction: r.awarenessCap / 100)
            Text(r.nextAt > 0 ? "At \(r.nextAt) outlets the name reaches further: more of the town can know you, demand is a little higher and goods are cheaper." : "A worldwide name.")
                .font(.caption2).foregroundStyle(Theme.ivoryFaint)
        }
    }
}

/// What in the chain needs the owner: stores losing money or out of cash, stores nobody manages, board items, franchise applicants.
struct ChainAttention: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var summary: Chains.Summary
    var currency: Currency
    @Binding var pending: PendingAction?

    var body: some View {
        let losing = summary.stores.filter { $0.status == .open && $0.profit < 0 }
        let unmanaged = summary.stores.filter { $0.status == .open && $0.managerName == nil }
        let broke = summary.stores.compactMap { engine.state.company($0.id) }.filter { $0.status == .open && $0.cash < 0 }
        let boardItems = engine.boardMeetings(key: "ch:\(summary.id)").filter { $0.status.isEmpty }.count
        let applicants = summary.franchisingCompanyID.map { engine.franchiseApplicants(companyID: $0).count } ?? 0
        if !losing.isEmpty || !unmanaged.isEmpty || !broke.isEmpty || boardItems > 0 || applicants > 0 {
            LedgerSection("Needs you") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(broke.enumerated()), id: \.element.id) { n, c in
                        if n > 0 { Hairline() }
                        lendRow(c)
                    }
                    if !losing.isEmpty {
                        if !broke.isEmpty { Hairline() }
                        line("\(losing.count) of \(summary.stores.count) stores lost money last month", losing.prefix(4).map { $0.name }.joined(separator: ", ") + (losing.count > 4 ? "…" : "") + ". Compare them below.", tint: Theme.loss)
                    }
                    if !unmanaged.isEmpty {
                        if !broke.isEmpty || !losing.isEmpty { Hairline() }
                        line("\(unmanaged.count) \(unmanaged.count == 1 ? "store has" : "stores have") no store manager", "You run \(unmanaged.count == 1 ? "it" : "them") yourself. Hire one in the store's Team, or let a chain manager fill them.", tint: Theme.caution)
                    }
                    if boardItems > 0 {
                        Hairline()
                        NavigationLink { BoardView(key: "ch:\(summary.id)") } label: {
                            GroupLinkRow(title: "The board has \(boardItems) \(boardItems == 1 ? "item" : "items") to decide", sub: "Approve or decline at the board.", subTint: Theme.caution)
                        }.buttonStyle(.plain)
                    }
                    if applicants > 0 {
                        Hairline()
                        line("\(applicants) franchise \(applicants == 1 ? "applicant is" : "applicants are") waiting", "Talk to them under Franchise your concept below.", tint: Theme.gain)
                    }
                }
            }
        }
    }

    private func line(_ title: String, _ sub: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 13.5)).foregroundStyle(tint)
            Text(sub).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 9)
    }

    /// A store out of cash can borrow from the sister store with the most to spare, repaid once it has a cushion again.
    private func lendRow(_ c: Company) -> some View {
        let weekly = engine.companyHealth(c).weeklyCost
        let need = currency.roundedStep(max(0, -c.cash) + weekly * 4, about: 1000)
        let owed = engine.groupLoanBalance(companyID: c.id)
        return HStack(alignment: .firstTextBaseline) {
            NavigationLink(value: CompanyRoute.companyAt(c.id, .finances)) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(c.name) is out of cash").font(.system(size: 13.5)).foregroundStyle(Theme.loss)
                    Text("Cash \(currency.tidyShort(c.cash))" + (owed > 0 ? " · already owes sister stores \(currency.tidyShort(owed))" : "")).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }
            }.buttonStyle(.plain)
            Spacer(minLength: 8)
            Button("Group loan \(currency.tidyShort(need))") {
                pending = PendingAction(title: "Lend \(currency.tidyShort(need)) to \(c.name)?",
                                        message: "The sister store with the most spare cash pays it, as a group loan. \(c.name) pays it back by itself once it has about ten weeks of costs again. Risk: the lending store has less of a cushion until then.",
                                        button: "Lend") {
                    let ok = store.act { $0.lendFromSister(companyID: c.id, amount: need) } ?? false
                    if ok { Haptics.success(); store.show("\(c.name) received a group loan of \(currency.tidyShort(need)).", tone: "good") }
                    else { Haptics.warning(); store.show("No sister store can spare that much right now.", tone: "warn") }
                }
            }.buttonStyle(QuietButtonStyle(tint: Theme.gold))
        }.padding(.vertical, 9)
    }
}

/// Every store side by side: sort, search, group by city, and open any store's company. Each store can take its own rules.
struct ChainStoreComparison: View {
    enum Sort: String, CaseIterable, Hashable { case profit = "Profit", revenue = "Revenue", city = "City", name = "Name" }
    var engine: GameEngine
    var summary: Chains.Summary
    var currency: Currency
    @State private var sort: Sort = .profit
    @State private var query = ""
    @State private var showAll = false
    @State private var openRulesFor: Int?

    private let pageSize = 12

    var body: some View {
        let all = sorted(summary.stores.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.cityName.localizedCaseInsensitiveContains(query) })
        let shown = showAll || query.count > 0 ? all : Array(all.prefix(pageSize))
        LedgerSection(title: "Stores", trailing: { Text("\(summary.stores.count)").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
            VStack(alignment: .leading, spacing: 0) {
                if summary.stores.count > 1 {
                    SectionTabs(items: Sort.allCases, title: { $0.rawValue }, selection: $sort).padding(.horizontal, -Theme.Space.margin)
                }
                if summary.stores.count > pageSize {
                    TextField("Search stores or cities", text: $query).textFieldStyle(.plain).font(.system(size: 14)).padding(.vertical, 8)
                        .overlay(alignment: .bottom) { Hairline() }
                }
                if all.isEmpty { Text("No store matches.").font(.caption).foregroundStyle(Theme.ivoryFaint).padding(.vertical, 8) }
                if sort == .city {
                    let cities = Array(Set(shown.map { $0.cityName })).sorted()
                    ForEach(cities, id: \.self) { city in
                        let list = shown.filter { $0.cityName == city }
                        HStack {
                            Text(city).capsLabel(Theme.ivoryFaint)
                            Spacer()
                            Text("\(list.count) · \(currency.tidyShort(list.reduce(0) { $0 + $1.profit })) / mo").font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.ivoryFaint)
                        }.padding(.top, 10)
                        ForEach(list) { s in row(s) }
                    }
                } else {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { n, s in
                        if n > 0 { Hairline() }
                        row(s)
                    }
                }
                if all.count > shown.count {
                    Button("Show all \(all.count) stores") { showAll = true }.font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold).buttonStyle(.plain).padding(.top, 8)
                }
            }
        }
    }

    private func sorted(_ l: [Chains.StoreLine]) -> [Chains.StoreLine] {
        switch sort {
        case .profit: return l.sorted { $0.profit > $1.profit }
        case .revenue: return l.sorted { $0.revenue > $1.revenue }
        case .city: return l.sorted { ($0.cityName, $0.name) < ($1.cityName, $1.name) }
        case .name: return l.sorted { $0.name < $1.name }
        }
    }

    @ViewBuilder private func row(_ s: Chains.StoreLine) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                NavigationLink(value: CompanyRoute.company(s.id)) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).lineLimit(1)
                        Text("\(s.cityName) · \(s.status == .setup ? "setting up" : s.managerName ?? "you run it") · \(s.staff) staff\(s.ownRules > 0 ? " · own rules" : "")")
                            .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(currency.tidyShort(s.profit)).font(.system(size: 13.5).monospacedDigit()).foregroundStyle(s.profit < 0 ? Theme.loss : Theme.ivory)
                    Text(currency.tidyShort(s.revenue) + " rev").font(.system(size: 10.5).monospacedDigit()).foregroundStyle(Theme.ivoryFaint)
                    Button(openRulesFor == s.id ? "Hide rules" : "Own rules") { openRulesFor = openRulesFor == s.id ? nil : s.id }
                        .font(.system(size: 11.5)).foregroundStyle(Theme.gold).buttonStyle(.plain)
                }
            }
            if openRulesFor == s.id { StoreRules(engine: engine, storeID: s.id) }
        }.padding(.vertical, 9)
    }
}

/// The rules every store of the chain follows.
struct ChainRulesSection: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var chainID: Int

    var body: some View {
        let rules = engine.chainRules(chainID: chainID)
        LedgerSection("Chain rules") {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("Set once for every store. A store can take its own price step, local marketing and pay under Own rules.").font(.caption).foregroundStyle(Theme.ivoryMuted)
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text("Price").font(.caption).foregroundStyle(Theme.ivoryMuted); Spacer(); Text(priceWord(rules["price"].double)).font(.system(size: 12.5)).foregroundStyle(Theme.ivory) }
                    Slider(value: Binding(get: { rules["price"].double }, set: { v in store.act { $0.setChainRule(chainID: chainID, rule: .price((v * 2).rounded() / 2)) } }), in: -3...3, step: 0.5)
                }
                Text("Ordering").font(.caption).foregroundStyle(Theme.ivoryMuted)
                SectionTabs(items: [0, 1, 2], title: { ["Lean", "Balanced", "Generous"][$0] },
                            selection: Binding(get: { rules["stockPol"].int }, set: { v in store.act { $0.setChainRule(chainID: chainID, rule: .stockPolicy(v)) } }))
                    .padding(.horizontal, -Theme.Space.margin)
                Text("Pay").font(.caption).foregroundStyle(Theme.ivoryMuted)
                SectionTabs(items: [0.0, 0.05, 0.1], title: { ["Market pay", "+5%", "+10%"][[0.0, 0.05, 0.1].firstIndex(of: $0) ?? 0] },
                            selection: Binding(get: { [0.0, 0.05, 0.1].min(by: { abs($0 - rules["pay"].double) < abs($1 - rules["pay"].double) }) ?? 0 },
                                               set: { v in store.act { $0.setChainRule(chainID: chainID, rule: .pay(v)) } }))
                    .padding(.horizontal, -Theme.Space.margin)
                Text("Marketing").font(.caption).foregroundStyle(Theme.ivoryMuted)
                SectionTabs(items: ["own", "light", "normal", "heavy"], title: { ["own": "Each store", "light": "Light", "normal": "Normal", "heavy": "Heavy"][$0] ?? $0 },
                            selection: Binding(get: { rules["mkt"].string.isEmpty ? "own" : rules["mkt"].string }, set: { v in store.act { $0.setChainRule(chainID: chainID, rule: .marketing(v)) } }))
                    .padding(.horizontal, -Theme.Space.margin)
                Text("Brand marketing takes a share of each store's sales for the two channels that suit the trade best. Pay is checked every month and anyone below the level gets a raise. Business choices and opening hours follow the chain.")
                    .font(.caption2).foregroundStyle(Theme.ivoryFaint)
            }
        }
    }

    private func priceWord(_ l: Double) -> String {
        switch l { case ..<(-1.9): return "Bargain"; case ..<(-0.4): return "Below market"; case ..<0.4: return "At market"; case ..<1.9: return "Premium"; default: return "Luxury" }
    }
}

/// Supply between your own companies that touches the chain: who supplies which store, and how much arrives.
struct ChainSupplyOverview: View {
    var engine: GameEngine
    var summary: Chains.Summary
    var currency: Currency

    var body: some View {
        let ids = Set(summary.stores.map { $0.id })
        let links = engine.supplyLinks().filter { ids.contains($0.buyerID) || ids.contains($0.supplierID) }
        LedgerSection(title: "Supply from your own companies", trailing: { Text("\(links.count)").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
            VStack(alignment: .leading, spacing: 0) {
                if links.isEmpty {
                    Text("No store buys from one of your own companies. Switch an input to your own supplier in a store's Chain section; the group keeps the margin.")
                        .font(.caption).foregroundStyle(Theme.ivoryFaint)
                }
                ForEach(Array(links.enumerated()), id: \.element.id) { n, l in
                    if n > 0 { Hairline() }
                    let buyer = engine.state.company(l.buyerID)?.name ?? "Store"
                    let supplier = engine.state.company(l.supplierID)?.name ?? "Supplier"
                    NavigationLink(value: CompanyRoute.companyAt(l.buyerID, .chain)) {
                        GroupLinkRow(title: "\(supplier) → \(buyer)",
                                     sub: "\(IntercompanySupply.kind(l.kindID)?.name ?? l.kindID) · \(IntercompanySupply.modeName(l.mode)) · \(Int((l.lastShare * 100).rounded()))% delivered",
                                     trailing: currency.tidyShort(l.lastSpend * l.lastShare * l.lastPriceFactor * 52) + " / yr",
                                     subTint: l.lastShare < 0.9 ? Theme.loss : Theme.ivoryFaint)
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

/// A new store under the chain's name and rules.
struct ChainNewStore: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var summary: Chains.Summary
    var currency: Currency
    @State private var newCity = ""
    @State private var newSize = 1.0
    @State private var pending: PendingAction?

    var body: some View {
        let cities = engine.state.company(summary.stores.first?.id ?? 0).flatMap { engine.data.countries[$0.countryCode] }?.cities ?? []
        let cityID = newCity.isEmpty ? (cities.first?.id ?? "") : newCity
        let cityName = cities.first { $0.id == cityID }?.name ?? ""
        let cost = engine.chainCost(chainID: summary.id, cityID: cityID, size: newSize)
        LedgerSection("New store") {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("Same name, same rules and the paperwork you already have. A new store needs premises, equipment and people; it is set up to the chain's standard and runs on the chain's rules from day one.")
                    .font(.caption).foregroundStyle(Theme.ivoryMuted)
                Picker("City", selection: Binding(get: { cityID }, set: { newCity = $0 })) {
                    ForEach(cities) { c in
                        let n = summary.stores.filter { $0.cityName == c.name }.count
                        Text(c.name + (n > 0 ? " · \(n) \(n == 1 ? "store" : "stores")" : "")).tag(c.id)
                    }
                }.pickerStyle(.menu)
                Picker("Size", selection: $newSize) { Text("Small").tag(0.7); Text("Standard").tag(1.0); Text("Large").tag(1.4) }.pickerStyle(.segmented)
                if let cost {
                    FlatRow(label: "Cost", value: currency.tidyShort(cost), sub: "You have \(store.money(Payments.liquid(engine.state))) available.", rule: false)
                    Button("Open \(summary.name) \(cityName)") {
                        pending = PendingAction(title: "Open \(summary.name) \(cityName)?",
                                                message: "About \(currency.tidyShort(cost)) now for premises, equipment and the first staff. The store takes a few weeks to set up and earns nothing until it opens; new stores start with fewer customers than the established ones.",
                                                button: "Open the store") { open(cityID: cityID) }
                    }.buttonStyle(GoldButtonStyle())
                } else {
                    Text("A new store is not possible in that city.").font(.caption).foregroundStyle(Theme.ivoryFaint)
                }
            }
        }
        .confirmAction($pending)
    }

    private func open(cityID: String) {
        switch store.act({ $0.openChainStore(chainID: summary.id, cityID: cityID, size: newSize) }) {
        case .success?: Haptics.success(); store.show("The new store is being set up.", tone: "good")
        case .failure(.notEnoughCash)?: Haptics.warning(); store.show("You don't have enough for a new store.", tone: "warn")
        default: Haptics.warning(); store.show("A new store is not possible here.", tone: "warn")
        }
    }
}

/// Your other companies of the same trade that could join the chain.
struct ChainJoin: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var summary: Chains.Summary

    var body: some View {
        let join = engine.companiesThatCanJoin(chainID: summary.id)
        if !join.isEmpty {
            LedgerSection("Add your other \((engine.data.catalog[summary.tradeID]?.name ?? "").lowercased()) companies") {
                VStack(spacing: 0) {
                    ForEach(Array(join.enumerated()), id: \.element.id) { n, c in
                        if n > 0 { Hairline() }
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                                Text(engine.cityName(c)).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                            }
                            Spacer()
                            Button("Add") { add(c, rename: false) }.buttonStyle(QuietButtonStyle())
                            Button("Add, rename") { add(c, rename: true) }.buttonStyle(QuietButtonStyle())
                        }.padding(.vertical, 8)
                    }
                    Text("A store that joins follows the chain's rules from then on; renamed, it carries the chain's name and awareness.").font(.caption2).foregroundStyle(Theme.ivoryFaint).padding(.top, 6)
                }
            }
        }
    }

    private func add(_ c: Company, rename: Bool) {
        store.act { $0.joinChain(chainID: summary.id, companyID: c.id, rename: rename) }
        if store.engine?.chainSummary(containing: c.id)?.id == summary.id { Haptics.success(); store.show("\(c.name) is now a store of \(summary.name).", tone: "good") }
        else { Haptics.warning(); store.show("\(c.name) could not join the chain.", tone: "warn") }
    }
}
