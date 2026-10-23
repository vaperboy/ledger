import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// A company's Chain section: its place in the chain (with the way to the chain page), how to grow into a chain, being a
/// franchisee (or, outside a chain, franchising it out), and supply between your own companies.
struct CompanyChain: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company

    var body: some View {
        let chain = engine.chainSummary(containing: company.id)
        let franchisee = !company.value("franchise").isNull
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if company.status == .open || company.status == .closed {
                if let sum = chain {
                    StoreInChainCard(engine: engine, company: company, summary: sum)
                } else if !franchisee {
                    GrowIntoChain(engine: engine, company: company)
                }
            }
            if franchisee {
                FranchiseeCard(engine: engine, company: company)
            } else if chain == nil && (engine.canFranchise(companyID: company.id) || engine.isFranchisor(companyID: company.id)) {
                // A chain franchises from its chain page; a company outside a chain sees what franchising needs here.
                FranchisorCard(engine: engine, company: company)
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

/// This store's place in its chain: the chain at a glance with a way to the chain page, how this store compares, its own rules and
/// what it owes sister stores. Chain-wide work (rules, all stores, chain posts, new stores) lives on the chain page.
struct StoreInChainCard: View {
    var engine: GameEngine
    var company: Company
    var summary: Chains.Summary

    var body: some View {
        let cur = engine.currency(for: company)
        let ranked = summary.stores.sorted { $0.profit > $1.profit }
        let rank = (ranked.firstIndex { $0.id == company.id } ?? 0) + 1
        let owed = engine.groupLoanBalance(companyID: company.id)
        LedgerSection(title: "Store of \(summary.name)", trailing: { Text("\(summary.stores.count) \(summary.stores.count == 1 ? "store" : "stores")").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
            VStack(alignment: .leading, spacing: 0) {
                NavigationLink { ChainView(chainID: summary.id) } label: {
                    GroupLinkRow(title: "Open the chain", sub: "All stores compared, chain rules, chain and regional managers, board, new stores · \(summary.reach.label)",
                                 trailing: cur.short(summary.profit) + " / mo", tint: summary.profit < 0 ? Theme.loss : Theme.ivory)
                }.buttonStyle(.plain)
                if summary.stores.count > 1 {
                    FlatRow(label: "This store", value: "No. \(rank) of \(summary.stores.count) by profit", sub: "Profit last month \(cur.short(summary.stores.first { $0.id == company.id }?.profit ?? 0)).")
                }
                if owed > 0 {
                    FlatRow(label: "Owes sister stores", value: cur.short(owed), sub: "A group loan, paid back by itself once the store has a cushion.", tint: Theme.caution)
                }
                Hairline()
                StoreRules(engine: engine, storeID: company.id).padding(.vertical, 9)
            }
        }
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
