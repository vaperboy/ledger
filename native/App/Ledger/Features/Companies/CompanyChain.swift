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
            MoreHeader(glyph: Glyph.group, title: "Chain", blurb: chainBlurb(chain: chain, franchisee: franchisee))
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
                CardRow(glyph: Glyph.market, title: "Suppliers and supply from your own companies", subtitle: "Who provides each input, prices, terms and risks. Switch provider in Operations.")
            }.buttonStyle(PressableStyle())
        }
    }

    private func chainBlurb(chain: Chains.Summary?, franchisee: Bool) -> String {
        if let chain { return "This store is one of \(chain.stores.count) in \(chain.name): its place, its own rules and the way to the chain page." }
        if franchisee { return "This company runs under a franchisor's agreement: its fees, rules and what you owe." }
        return "Grow this company into a chain, or franchise the concept out to other owners."
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
    @State private var signing = false

    var body: some View {
        let reqs = engine.chainRequirements(companyID: company.id)
        let doc = engine.documentState(companyID: company.id, document: "chain")
        let ready: Int = reqs.filter { $0.ok }.count
        VStack(alignment: .leading, spacing: 16) {
            MoreBlock(title: "Grow into a chain", trailing: { Text("\(ready) of \(reqs.count) ready").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint) }) {
                VStack(alignment: .leading, spacing: 10) {
                    RateBar(label: "Ready", fraction: reqs.isEmpty ? 0 : Double(ready) / Double(reqs.count), tint: ready == reqs.count ? Theme.gain : Theme.gold)
                    CardLine()
                    RequirementGuide(engine: engine, company: company, requirements: reqs)
                }
            }
            if let lock = engine.unlockItem("chain", companyID: company.id), !lock.unlocked {
                LockedBlock(title: "Chain registration", reason: lock.reason, progress: Double(Unlocks.weeksTraded(engine.state, company)) / Double(Unlocks.weeksChain))
            } else {
                registration(doc.status, weeksLeft: doc.weeksLeft, blocked: reqs.contains { !$0.ok })
            }
        }
        .onAppear { if name.isEmpty { name = company.name } }
    }

    @ViewBuilder private func registration(_ status: String, weeksLeft: Int, blocked: Bool) -> some View {
        let cur: Currency = engine.currency(for: company)
        if status == "applied" {
            NoteCard(text: "Chain registration is in progress: about \(weeksLeft) \(weeksLeft == 1 ? "week" : "weeks") left. The lawyer is writing the operations manual.", glyph: Glyph.clock, tint: Theme.caution)
        } else if status == "ok" {
            MoreBlock("Name the chain") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Chain approved. Name the chain: every store will carry this name.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                    Card(padding: 10, radius: Theme.Radius.table) {
                        TextField("Chain name", text: $name).textFieldStyle(.plain).font(.system(size: 15))
                    }
                    QuietButton(title: "Make \(name.isEmpty ? company.name : name) a chain", fullWidth: true) {
                        let made: Int? = store.act({ $0.makeChain(companyID: company.id, name: name.isEmpty ? company.name : name) }) ?? nil
                        if made != nil { Haptics.success(); store.show("It is now a chain. Add stores or open new ones.", tone: "good") }
                        else { Haptics.warning(); store.show("The chain registration is not approved yet.", tone: "warn") }
                    }
                }
            }
        } else {
            QuietButton(title: "Apply for chain registration · \(cur.tidyShort(engine.documentFee(companyID: company.id, document: "chain")))", fullWidth: true) {
                signing = true
            }
            .disabled(blocked).opacity(blocked ? 0.5 : 1)
            .centerSheet(isPresented: $signing) {
                PaperSignSheet(title: "Chain registration", to: "The business register", note: "A lawyer prepares the registration of \(company.name) as a chain. It is reviewed before it is approved.",
                               fee: cur.tidyShort(engine.documentFee(companyID: company.id, document: "chain")), wait: "after a review of some weeks", button: "Sign and send",
                               onSend: {
                    switch store.act({ $0.applyForChainDocument(companyID: company.id, document: "chain") }) {
                    case .ok?: Haptics.success(); store.show("Application sent.", tone: "good")
                    case .notYet(let why)?: Haptics.warning(); store.show(why, tone: "warn")
                    case .notEnoughCash?: Haptics.warning(); store.show("Not enough cash in the company for the lawyer.", tone: "warn")
                    default: Haptics.warning(); store.show("The application could not be sent.", tone: "warn")
                    }
                }, onClose: { signing = false })
                .environment(\.outsidePalette, OutsidePalette.game).presentationBackground(.clear)
            }
        }
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
        let mine: Double = summary.stores.first { $0.id == company.id }?.profit ?? 0
        MoreBlock(title: "Store of \(summary.name)", card: false, trailing: { Text("\(summary.stores.count) \(summary.stores.count == 1 ? "store" : "stores")").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint) }) {
            NavigationLink { ChainView(chainID: summary.id) } label: {
                CardRow(glyph: Glyph.group, title: "Open the chain", subtitle: "All stores compared, chain rules, chain and regional managers, board, new stores · \(summary.reach.label)",
                        value: cur.tidyShort(summary.profit) + " / mo", valueTint: summary.profit < 0 ? Theme.loss : Theme.ivory)
            }.buttonStyle(PressableStyle())
            if summary.stores.count > 1 || owed > 0 {
                standing(rank: rank, mine: mine, owed: owed, cur: cur)
            }
            EntityCard { StoreRules(engine: engine, storeID: company.id) }
        }
    }

    private func standing(rank: Int, mine: Double, owed: Double, cur: Currency) -> some View {
        var items: [KeyFigures.Item] = []
        if summary.stores.count > 1 {
            items.append(.init(label: "Rank by profit", value: "No. \(rank) of \(summary.stores.count)"))
            items.append(.init(label: "Profit last month", value: cur.tidyShort(mine), tint: mine < 0 ? Theme.loss : Theme.ivory))
        }
        if owed > 0 { items.append(.init(label: "Owes sister stores", value: cur.tidyShort(owed), tint: Theme.caution, sub: "group loan")) }
        let columns: Int = max(1, min(3, items.count))
        return Card(padding: 14, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 10) {
                FigureStrip(items: items, columns: columns)
                if owed > 0 { Text("A group loan, paid back by itself once the store has a cushion.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint) }
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
                    Button(v == 0 ? "Chain" : v < 0 ? "Lower" : "Higher") { store.settle(store.act { $0.setStoreRule(companyID: storeID, rule: .priceSteps(v)) }, "Store price rule saved.", same: "That price rule is already set.") }
                        .buttonStyle(TinyButtonStyle(tint: off["price"].double == v ? Theme.gold : Theme.ivoryFaint))
                }
            }
            HStack {
                Text("Local marketing").font(.caption).foregroundStyle(Theme.ivoryMuted)
                Spacer()
                ForEach([0.0, 0.01, 0.02], id: \.self) { v in
                    Button(v == 0 ? "None extra" : "+\(Int(v * 100))%") { store.settle(store.act { $0.setStoreRule(companyID: storeID, rule: .marketing(v)) }, "Store marketing rule saved.", same: "That marketing rule is already set.") }
                        .buttonStyle(TinyButtonStyle(tint: off["mkt"].double == v ? Theme.gold : Theme.ivoryFaint))
                }
            }
            HStack {
                Text("Pay").font(.caption).foregroundStyle(Theme.ivoryMuted)
                Spacer()
                ForEach([-0.1, 0.0, 0.1], id: \.self) { v in
                    Button(v == 0 ? "Chain pay" : v < 0 ? "−10%" : "+10%") { store.settle(store.act { $0.setStoreRule(companyID: storeID, rule: .pay(v)) }, "Store pay rule saved.", same: "That pay rule is already set.") }
                        .buttonStyle(TinyButtonStyle(tint: off["pay"].double == v ? Theme.gold : Theme.ivoryFaint))
                }
            }
        }
    }
}
