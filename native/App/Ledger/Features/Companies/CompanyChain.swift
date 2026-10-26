import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// A company's Chain section: its place in the chain (with the way to the chain page), how to grow into a chain, being a
/// franchisee (or, outside a chain, franchising it out). Supply between your own companies is in Operations > Suppliers.
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
            // Supply between your own companies lives in Operations > Suppliers (one record, one action).
            NavigationLink(value: CompanyRoute.companyAt(company.id, .operations)) {
                GroupLinkRow(title: "Suppliers and supply from your own companies", sub: "Who provides each input, prices, terms and risks. Switch provider in Operations.")
            }.buttonStyle(.plain)
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
                        Text(r.title.tidyMoney).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                        Spacer(minLength: 8)
                        Text(r.detail.tidyMoney).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).multilineTextAlignment(.trailing)
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
                    Button("Apply for chain registration · \(cur.tidyShort(engine.documentFee(companyID: company.id, document: "chain")))") {
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
                                 trailing: cur.tidyShort(summary.profit) + " / mo", tint: summary.profit < 0 ? Theme.loss : Theme.ivory)
                }.buttonStyle(.plain)
                if summary.stores.count > 1 {
                    FlatRow(label: "This store", value: "No. \(rank) of \(summary.stores.count) by profit", sub: "Profit last month \(cur.tidyShort(summary.stores.first { $0.id == company.id }?.profit ?? 0)).")
                }
                if owed > 0 {
                    FlatRow(label: "Owes sister stores", value: cur.tidyShort(owed), sub: "A group loan, paid back by itself once the store has a cushion.", tint: Theme.caution)
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
