import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// A company's Chain section: the chain it belongs to (stores, shared rules, reach), how to grow into one, franchising it out
/// or being a franchisee, and supply between your own companies.
struct CompanyChain: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if company.status == .open || company.status == .closed {
                if let sum = engine.chainSummary(containing: company.id) {
                    ChainOverview(engine: engine, company: company, summary: sum)
                    ChainStaffShortages(engine: engine, chainID: sum.id)
                    ExecutivePosts(engine: engine, chainID: sum.id)
                } else if company.value("franchise").isNull {
                    GrowIntoChain(engine: engine, company: company)
                }
            }
            if engine.canFranchise(companyID: company.id) || !company.value("franchise").isNull {
                CompanyFranchise(engine: engine, company: company)
            }
            CompanySupply(engine: engine, company: company)
        }
    }

    /// Whether the Chain section has anything to show for this company.
    static func isRelevant(_ co: Company, _ e: GameEngine) -> Bool {
        co.type != "hold" && co.type != "club" && (co.status == .open || co.status == .closed)
    }
}

/// The checklist before a chain: what the first store has to prove, then registration, then naming the chain.
struct GrowIntoChain: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var name = ""

    var body: some View {
        let reqs = engine.chainRequirements(companyID: company.id)
        let doc = engine.documentState(companyID: company.id, document: "chain")
        let cur = engine.currency(for: company)
        LedgerSection(title: "Grow into a chain", trailing: { Text("\(reqs.filter { $0.ok }.count) of \(reqs.count) ready").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
            VStack(alignment: .leading, spacing: 0) {
                Text("A second store comes when the first one has proven itself. Register the chain, have a lawyer write the operations manual every store follows, then open more stores under the same name.")
                    .font(.caption).foregroundStyle(Theme.ivoryMuted).padding(.bottom, 8)
                ForEach(Array(reqs.enumerated()), id: \.element.id) { n, r in
                    if n > 0 { Hairline() }
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: r.ok ? "checkmark" : "circle").font(.system(size: 11)).foregroundStyle(r.ok ? Theme.gain : Theme.ivoryFaint).frame(width: 18)
                        Text(r.title).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                        Spacer(minLength: 8)
                        Text(r.detail).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).multilineTextAlignment(.trailing)
                    }.padding(.vertical, 8)
                }
                Hairline()
                if doc.status == "applied" {
                    Text("Chain registration is in progress: about \(doc.weeksLeft) \(doc.weeksLeft == 1 ? "week" : "weeks") left. The lawyer is writing the operations manual.")
                        .font(.caption).foregroundStyle(Theme.caution).padding(.top, 10)
                } else if doc.status == "ok" {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text("Chain approved. Name the chain: every store will carry this name.").font(.caption).foregroundStyle(Theme.ivoryMuted)
                        TextField("Chain name", text: $name).textFieldStyle(.plain).font(.system(size: 15)).padding(.vertical, 8)
                            .overlay(alignment: .bottom) { Hairline() }
                        Button("Make \(name.isEmpty ? company.name : name) a chain") {
                            let made: Int? = store.act({ $0.makeChain(companyID: company.id, name: name.isEmpty ? company.name : name) }) ?? nil
                            if made != nil { Haptics.success(); store.show("It is now a chain. Add stores or open new ones.", tone: "good") }
                            else { Haptics.warning(); store.show("The chain registration is not approved yet.", tone: "warn") }
                        }.buttonStyle(GoldButtonStyle())
                    }.padding(.top, 10)
                } else {
                    Button("Apply for chain registration · \(cur.short(engine.documentFee(companyID: company.id, document: "chain")))") {
                        switch store.act({ $0.applyForChainDocument(companyID: company.id, document: "chain") }) {
                        case .ok?: Haptics.success(); store.show("Application sent.", tone: "good")
                        case .notYet(let why)?: Haptics.warning(); store.show(why, tone: "warn")
                        case .notEnoughCash?: Haptics.warning(); store.show("Not enough cash in the company for the lawyer.", tone: "warn")
                        default: break
                        }
                    }.buttonStyle(QuietButtonStyle()).padding(.top, 10).disabled(reqs.contains { !$0.ok })
                }
            }
        }
        .onAppear { if name.isEmpty { name = company.name } }
    }
}

/// A registered chain: how the stores do, how far the name reaches, the rules every store follows, and a new store.
struct ChainOverview: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    var summary: Chains.Summary
    @State private var openRulesFor: Int?
    @State private var newCity = ""
    @State private var newSize = 1.0

    var body: some View {
        let cur = engine.currency(for: company)
        let rules = engine.chainRules(chainID: summary.id)
        let r = summary.reach
        LedgerSection(title: summary.name, trailing: { Text("\(summary.stores.count) \(summary.stores.count == 1 ? "store" : "stores")").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                KeyFigures(items: [
                    .init(label: "Revenue / mo", value: cur.short(summary.revenue)),
                    .init(label: "Profit / mo", value: cur.short(summary.profit), tint: summary.profit < 0 ? Theme.loss : Theme.ivory),
                    .init(label: "Staff", value: "\(summary.staff)"),
                    .init(label: "Reach", value: r.label, sub: "\(r.outlets) outlets"),
                    .init(label: "Buying discount", value: String(format: "%.1f%%", r.rebate * 100), sub: "of cost of sales"),
                    .init(label: "Franchise units", value: "\(summary.franchiseUnits)"),
                ])
                RateBar(label: "Name known by", fraction: r.awarenessCap / 100)
                Text(r.nextAt > 0 ? "One shop is a local name. At \(r.nextAt) outlets the name reaches further (more of the town can know you, demand is a little higher, goods are cheaper)." : "A worldwide name.")
                    .font(.caption2).foregroundStyle(Theme.ivoryFaint)
            }
        }
        LedgerSection("Stores") {
            VStack(spacing: 0) {
                ForEach(Array(summary.stores.enumerated()), id: \.element.id) { n, s in
                    if n > 0 { Hairline() }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            NavigationLink(value: CompanyRoute.company(s.id)) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(s.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).lineLimit(1)
                                    Text("\(s.cityName) · \(s.status == .setup ? "setting up" : s.managerName ?? "you run it") · \(s.staff) staff\(s.ownRules > 0 ? " · own rules" : "")")
                                        .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                                }
                            }.buttonStyle(.plain)
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(cur.short(s.profit)).font(.system(size: 13.5).monospacedDigit()).foregroundStyle(s.profit < 0 ? Theme.loss : Theme.ivory)
                                Button(openRulesFor == s.id ? "Hide rules" : "Own rules") { openRulesFor = openRulesFor == s.id ? nil : s.id }
                                    .font(.system(size: 11.5)).foregroundStyle(Theme.gold).buttonStyle(.plain)
                            }
                        }
                        if openRulesFor == s.id { StoreRules(engine: engine, storeID: s.id) }
                    }.padding(.vertical, 9)
                }
            }
        }
        LedgerSection("Chain rules") {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("Set once for every store. A store can take its own price step, local marketing, pay and ordering under Own rules.").font(.caption).foregroundStyle(Theme.ivoryMuted)
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text("Price").font(.caption).foregroundStyle(Theme.ivoryMuted); Spacer(); Text(priceWord(rules["price"].double)).font(.system(size: 12.5)).foregroundStyle(Theme.ivory) }
                    Slider(value: Binding(get: { rules["price"].double }, set: { v in store.act { $0.setChainRule(chainID: summary.id, rule: .price((v * 2).rounded() / 2)) } }), in: -3...3, step: 0.5)
                }
                Text("Ordering").font(.caption).foregroundStyle(Theme.ivoryMuted)
                SectionTabs(items: [0, 1, 2], title: { ["Lean", "Balanced", "Generous"][$0] },
                            selection: Binding(get: { rules["stockPol"].int }, set: { v in store.act { $0.setChainRule(chainID: summary.id, rule: .stockPolicy(v)) } }))
                    .padding(.horizontal, -Theme.Space.margin)
                Text("Pay").font(.caption).foregroundStyle(Theme.ivoryMuted)
                SectionTabs(items: [0.0, 0.05, 0.1], title: { ["Market pay", "+5%", "+10%"][[0.0, 0.05, 0.1].firstIndex(of: $0) ?? 0] },
                            selection: Binding(get: { [0.0, 0.05, 0.1].min(by: { abs($0 - rules["pay"].double) < abs($1 - rules["pay"].double) }) ?? 0 },
                                               set: { v in store.act { $0.setChainRule(chainID: summary.id, rule: .pay(v)) } }))
                    .padding(.horizontal, -Theme.Space.margin)
                Text("Marketing").font(.caption).foregroundStyle(Theme.ivoryMuted)
                SectionTabs(items: ["own", "light", "normal", "heavy"], title: { ["own": "Each store", "light": "Light", "normal": "Normal", "heavy": "Heavy"][$0] ?? $0 },
                            selection: Binding(get: { rules["mkt"].string.isEmpty ? "own" : rules["mkt"].string }, set: { v in store.act { $0.setChainRule(chainID: summary.id, rule: .marketing(v)) } }))
                    .padding(.horizontal, -Theme.Space.margin)
                Text("Marketing for the whole brand: a share of each store's sales goes to the two channels that suit the trade best. Pay is checked every month and anyone below the level gets a raise. Business choices and opening hours follow the chain.")
                    .font(.caption2).foregroundStyle(Theme.ivoryFaint)
            }
        }
        newStore(cur: cur)
        let join = engine.companiesThatCanJoin(chainID: summary.id)
        if !join.isEmpty {
            LedgerSection("Add your other \(engine.tradeName(company).lowercased()) companies") {
                VStack(spacing: 0) {
                    ForEach(Array(join.enumerated()), id: \.element.id) { n, c in
                        if n > 0 { Hairline() }
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                                Text(engine.cityName(c)).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                            }
                            Spacer()
                            Button("Add") { store.act { $0.joinChain(chainID: summary.id, companyID: c.id, rename: false) }; Haptics.success() }.buttonStyle(QuietButtonStyle())
                            Button("Add, rename") { store.act { $0.joinChain(chainID: summary.id, companyID: c.id, rename: true) }; Haptics.success() }.buttonStyle(QuietButtonStyle())
                        }.padding(.vertical, 8)
                    }
                }
            }
        }
    }

    @ViewBuilder private func newStore(cur: Currency) -> some View {
        let cities = engine.state.company(summary.stores.first?.id ?? 0).flatMap { engine.data.countries[$0.countryCode] }?.cities ?? []
        let cityID = newCity.isEmpty ? (cities.first?.id ?? "") : newCity
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
                    FlatRow(label: "Cost", value: cur.short(cost), sub: "You have \(store.money(Payments.liquid(engine.state))) available.", rule: false)
                    Button("Open \(summary.name) \(cities.first { $0.id == cityID }?.name ?? "")") {
                        switch store.act({ $0.openChainStore(chainID: summary.id, cityID: cityID, size: newSize) }) {
                        case .success?: Haptics.success(); store.show("The new store is being set up.", tone: "good")
                        case .failure(.notEnoughCash)?: Haptics.warning(); store.show("You don't have enough for a new store.", tone: "warn")
                        default: Haptics.warning(); store.show("A new store is not possible here.", tone: "warn")
                        }
                    }.buttonStyle(GoldButtonStyle())
                }
            }
        }
    }

    private func priceWord(_ l: Double) -> String {
        switch l { case ..<(-1.9): return "Bargain"; case ..<(-0.4): return "Below market"; case ..<0.4: return "At market"; case ..<1.9: return "Premium"; default: return "Luxury" }
    }
}

/// One store's own rules on top of the chain's.
struct StoreRules: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var storeID: Int

    var body: some View {
        let off = engine.state.company(storeID)?.value("off") ?? .null
        VStack(alignment: .leading, spacing: 6) {
            Text("Own rules for this store").capsLabel(Theme.ivoryFaint)
            HStack {
                Text("Price step").font(.caption).foregroundStyle(Theme.ivoryMuted)
                Spacer()
                ForEach([-1.0, 0.0, 1.0], id: \.self) { v in
                    Button(v == 0 ? "Chain" : v < 0 ? "Lower" : "Higher") { store.act { $0.setStoreRule(companyID: storeID, rule: .priceSteps(v)) } }
                        .buttonStyle(QuietButtonStyle(tint: off["price"].double == v ? Theme.gold : Theme.ivoryFaint))
                }
            }
            HStack {
                Text("Local marketing").font(.caption).foregroundStyle(Theme.ivoryMuted)
                Spacer()
                ForEach([0.0, 0.01, 0.02], id: \.self) { v in
                    Button(v == 0 ? "None extra" : "+\(Int(v * 100))%") { store.act { $0.setStoreRule(companyID: storeID, rule: .marketing(v)) } }
                        .buttonStyle(QuietButtonStyle(tint: off["mkt"].double == v ? Theme.gold : Theme.ivoryFaint))
                }
            }
            HStack {
                Text("Pay").font(.caption).foregroundStyle(Theme.ivoryMuted)
                Spacer()
                ForEach([-0.1, 0.0, 0.1], id: \.self) { v in
                    Button(v == 0 ? "Chain pay" : v < 0 ? "−10%" : "+10%") { store.act { $0.setStoreRule(companyID: storeID, rule: .pay(v)) } }
                        .buttonStyle(QuietButtonStyle(tint: off["pay"].double == v ? Theme.gold : Theme.ivoryFaint))
                }
            }
        }
    }
}

/// Supply between your own companies: what this company buys that another of yours could supply, and what it supplies.
struct CompanySupply: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var picking: String?

    var body: some View {
        let kinds = engine.supplyKinds(companyID: company.id)
        let sells = engine.supplyLinks().filter { $0.supplierID == company.id }
        let cur = engine.currency(for: company)
        let shown = kinds.filter { engine.supplyLink(buyer: company.id, kind: $0.id) != nil || !engine.possibleSuppliers(buyer: company.id, kind: $0.id).isEmpty
            || engine.accountSupplyLink(buyer: company.id, kind: $0.id) != nil || !engine.accountSupplyCandidates(buyer: company.id, kind: $0.id).isEmpty }
        if !shown.isEmpty || !sells.isEmpty {
            LedgerSection("Supply from your own companies") {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Switch an input from outside suppliers to one of your own companies, at market price, cost plus 10% or cost. The supplier gets the volume, the group keeps the margin, and if the supplier struggles the buyer pays for emergency supply.")
                        .font(.caption).foregroundStyle(Theme.ivoryMuted).padding(.bottom, 6)
                    ForEach(Array(shown.enumerated()), id: \.element.id) { n, k in
                        if n > 0 { Hairline() }
                        buyRow(k, cur: cur)
                    }
                    ForEach(Array(sells.enumerated()), id: \.element.id) { n, l in
                        if let b = engine.state.company(l.buyerID), let k = IntercompanySupply.kind(l.kindID) {
                            Hairline()
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Supplies \(b.name)").font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                                    Text("\(k.name) · \(IntercompanySupply.modeName(l.mode)) · \(Int((l.lastShare * 100).rounded()))% delivered").font(.system(size: 11)).foregroundStyle(l.lastShare < 0.9 ? Theme.loss : Theme.ivoryFaint)
                                }
                                Spacer(minLength: 8)
                                Text(cur.short(l.lastSpend * l.lastShare * l.lastPriceFactor * 52) + " / yr").font(.system(size: 13.5).monospacedDigit())
                            }.padding(.vertical, 9)
                        }
                    }
                    if company.num("int27u") > 0 {
                        Text("Holding back \(Int(company.num("int27u").rounded())) sales a week of its capacity for the group.").font(.caption2).foregroundStyle(Theme.ivoryFaint).padding(.top, 4)
                    }
                }
            }
        }
    }

    @ViewBuilder private func buyRow(_ k: IntercompanySupply.Kind, cur: Currency) -> some View {
        let link = engine.supplyLink(buyer: company.id, kind: k.id)
        let supplier = link.flatMap { engine.state.company($0.supplierID) }
        let year = engine.yearlySupplySpend(buyer: company.id, kind: k.id)
        let acct = engine.accountSupplyLink(buyer: company.id, kind: k.id)
        let customers = engine.accountSupplyCandidates(buyer: company.id, kind: k.id)
        let acctName = acct.flatMap { l in customers.first { $0.accountID == l.accountID }?.accountName }
        VStack(alignment: .leading, spacing: 6) {
            Button { picking = picking == k.id ? nil : k.id } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(supplier?.name ?? acctName ?? "Outside suppliers").font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                        Text(acct != nil && link == nil ? "\(k.name) · business customer · saves \(cur.short(acct!.savedSoFar)) so far"
                             : "\(k.name) · \(link.map { IntercompanySupply.modeName($0.mode) } ?? "about \(cur.short(year)) a year")\(link != nil ? " · saves \(cur.short(link!.saved)) so far" : "")")
                            .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                    }
                    Spacer(minLength: 8)
                    Chip(text: link == nil ? (acct == nil ? "Outside" : "Customer") : (link!.lastShare < 0.9 ? "Short" : "Yours"), tint: link == nil ? (acct == nil ? Theme.ivoryMuted : Theme.gain) : (link!.lastShare < 0.9 ? Theme.loss : Theme.gain))
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if picking == k.id {
                let options = engine.possibleSuppliers(buyer: company.id, kind: k.id)
                ForEach(options) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.name).font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
                        HStack {
                            ForEach(IntercompanySupply.modes, id: \.id) { m in
                                let pf = engine.supplyPriceFactor(supplier: s.id, mode: m.id)
                                Button(m.name + (pf < 1 ? " · saves \(cur.short(year * (1 - pf)))" : "")) {
                                    if store.act({ $0.setSupplier(buyer: company.id, kind: k.id, supplier: s.id, mode: m.id) }) == true { Haptics.success(); picking = nil }
                                }.buttonStyle(QuietButtonStyle(tint: link?.supplierID == s.id && link?.mode == m.id ? Theme.gold : Theme.ivoryMuted)).font(.caption)
                            }
                        }
                    }
                }
                if !customers.isEmpty {
                    Text("Your business customers").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ivoryMuted).padding(.top, 4)
                    ForEach(customers) { c in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.accountName).font(.system(size: 13)).foregroundStyle(Theme.ivory)
                                Text(c.canBuy ? "\(Rivals.relationshipWord(c.relationship)) · buys from \(c.ownerCompanyName) · \(Int(((1 - c.priceFactor) * 100).rounded()))% below the outside price"
                                     : "Get to know them better first (familiar or closer).").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                            }
                            Spacer(minLength: 8)
                            if acct?.accountID == c.accountID { Chip(text: "Current", tint: Theme.gain) }
                            else if c.canBuy {
                                Button("Buy · saves \(cur.short(c.yearlySaving)) a year") {
                                    if store.act({ $0.buyFromAccount(buyer: company.id, kind: k.id, accountID: c.accountID) }) == .ok { Haptics.success(); picking = nil }
                                }.buttonStyle(QuietButtonStyle(tint: Theme.gold)).font(.caption)
                            }
                        }
                    }
                }
                if acct != nil { Button("Stop buying from the business customer") { store.act { $0.stopBuyingFromAccount(buyer: company.id, kind: k.id) }; picking = nil }.font(.system(size: 12)).foregroundStyle(Theme.loss).buttonStyle(.plain) }
                if link != nil { Button("Back to outside suppliers") { store.act { $0.clearSupplier(buyer: company.id, kind: k.id) }; picking = nil }.font(.system(size: 12)).foregroundStyle(Theme.loss).buttonStyle(.plain) }
                Text("Market price keeps the profit in the supplier; at cost it moves to the buyer. If the supplier is short of people or closes, the buyer pays for emergency supply and its customers notice.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
            }
        }.padding(.vertical, 9)
    }
}
