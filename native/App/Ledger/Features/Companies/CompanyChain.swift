import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

enum CompanyChain {
    static func isRelevant(_ co: Company, _ e: GameEngine) -> Bool {
        co.type != "hold" && co.type != "club" && (co.status == .open || co.status == .closed)
    }
}

struct GrowIntoChain: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var name = ""

    var body: some View {
        if engine.levelOpen(.chain) {
            MoreBlock("Start a chain") {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Text("Every store you add carries one name and one set of rules.").textStyle(.caption, tint: Theme.inkSoft)
                    Card(padding: Theme.Space.m, radius: Theme.Radius.table, fill: Theme.inset) {
                        TextField("Chain name", text: $name).textFieldStyle(.plain).font(.system(size: 15))
                    }
                    PrimaryAction(title: "Start a chain", identifier: "chain-make") { start() }
                }
            }
            .onAppear { if name.isEmpty { name = company.name } }
        } else {
            LevelLockCard(feature: .chain)
        }
    }

    private func start() {
        let chosen: String = name.trimmingCharacters(in: .whitespaces)
        let made: Int? = store.act({ $0.startChain(companyID: company.id, name: chosen.isEmpty ? company.name : chosen) }) ?? nil
        if made != nil { Haptics.success(); store.show("It is now a chain. Add stores or open new ones.", tone: "good") }
        else { Haptics.warning(); store.show("A chain cannot be started yet.", tone: "warn") }
    }
}

struct StoreInChainCard: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    var summary: Chains.Summary

    var body: some View {
        let cur = engine.currency(for: company)
        let ranked = summary.stores.sorted { $0.profit > $1.profit }
        let rank = (ranked.firstIndex { $0.id == company.id } ?? 0) + 1
        let owed = engine.groupLoanBalance(companyID: company.id)
        let mine: Double = summary.stores.first { $0.id == company.id }?.profit ?? 0
        MoreBlock(title: "Store of \(summary.name)", card: false, trailing: { Text("\(summary.stores.count) \(summary.stores.count == 1 ? "store" : "stores")").textStyle(.caption, tint: Theme.inkFaint) }) {
            placeLine
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

    @ViewBuilder private var placeLine: some View {
        if let pos = engine.branchParent(companyID: company.id) {
            let gm: GroupManagement? = store.memo("groupMgmt") { (e: GameEngine) -> GroupManagement in e.groupManagement() }
            let place: String = pos.index == 1 ? "Head-office store of " + summary.name : "Branch \(pos.index) of \(pos.count) of " + summary.name
            let runner: String = ChainWords.runnerName(gm, companyID: company.id)
            let owner: String = ChainWords.lowered(ChainWords.ownerText(engine, companyID: company.id))
            Text(place + ", run by " + runner + ", " + owner)
                .textStyle(.caption, tint: Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Space.xxs)
                .accessibilityIdentifier("store-chain-place")
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
        return Card(padding: Theme.Space.l, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                FigureStrip(items: items, columns: columns)
                if owed > 0 { Text("A group loan, paid back by itself once the store has a cushion.").textStyle(.caption, tint: Theme.inkFaint) }
            }
        }
    }
}

struct StoreRules: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var storeID: Int

    var body: some View {
        let off = engine.state.company(storeID)?.value("off") ?? .null
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Own rules for this store").capsLabel(Theme.ivoryFaint)
            HStack {
                Text("Price step").textStyle(.caption, tint: Theme.inkSoft)
                Spacer()
                ForEach([-1.0, 0.0, 1.0], id: \.self) { v in
                    Button(v == 0 ? "Chain" : v < 0 ? "Lower" : "Higher") { store.settle(store.act { $0.setStoreRule(companyID: storeID, rule: .priceSteps(v)) }, "Store price rule saved.", same: "That price rule is already set.") }
                        .buttonStyle(TinyButtonStyle(tint: off["price"].double == v ? Theme.gold : Theme.ivoryFaint))
                }
            }
            HStack {
                Text("Local marketing").textStyle(.caption, tint: Theme.inkSoft)
                Spacer()
                ForEach([0.0, 0.01, 0.02], id: \.self) { v in
                    Button(v == 0 ? "None extra" : "+\(Int(v * 100))%") { store.settle(store.act { $0.setStoreRule(companyID: storeID, rule: .marketing(v)) }, "Store marketing rule saved.", same: "That marketing rule is already set.") }
                        .buttonStyle(TinyButtonStyle(tint: off["mkt"].double == v ? Theme.gold : Theme.ivoryFaint))
                }
            }
            HStack {
                Text("Pay").textStyle(.caption, tint: Theme.inkSoft)
                Spacer()
                ForEach([-0.1, 0.0, 0.1], id: \.self) { v in
                    Button(v == 0 ? "Chain pay" : v < 0 ? "−10%" : "+10%") { store.settle(store.act { $0.setStoreRule(companyID: storeID, rule: .pay(v)) }, "Store pay rule saved.", same: "That pay rule is already set.") }
                        .buttonStyle(TinyButtonStyle(tint: off["pay"].double == v ? Theme.gold : Theme.ivoryFaint))
                }
            }
        }
    }
}
