import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// The chain's view of the same Suppliers record as a store's Operations > Suppliers: for each input, who the stores use, which provider is
/// the usual one and which stores differ (the exceptions), and the chain-wide rule. A rule makes one provider the chain's mandatory choice for
/// an input, exactly like a chain standard for how you sell: each store switches on its own terms, a store that cannot (the provider does not
/// serve it, an own company has no spare capacity) keeps its choice and is listed with the reason, a franchised unit follows only what its
/// agreement fixes, and "Each store decides" releases the rule. Each exception opens that store's Suppliers section.
struct ChainSupplyOverview: View {
    @EnvironmentObject var store: GameStore
    @State private var pending: PendingAction?
    var engine: GameEngine
    var summary: Chains.Summary
    var currency: Currency

    private struct Entry { var storeID: Int; var store: String; var provider: String }
    private struct Row: Identifiable {
        var id: String
        var title: String
        var byStore: [Entry]
        var usual: String
        var usualCount: Int
        var exceptions: [Entry] { byStore.filter { $0.provider != usual } }
    }

    private func rows() -> [Row] {
        var order: [String] = []
        var titles: [String: String] = [:]
        var by: [String: [Entry]] = [:]
        for st in summary.stores where st.status.isLive {
            for p in engine.supplierCurrentProviders(companyID: st.id) {
                if titles[p.inputID] == nil { order.append(p.inputID); titles[p.inputID] = p.title }
                by[p.inputID, default: []].append(Entry(storeID: st.id, store: st.name, provider: p.provider))
            }
        }
        return order.map { id in
            let list = by[id] ?? []
            let counts = Dictionary(grouping: list, by: { $0.provider }).mapValues { $0.count }
            let top = counts.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }
            return Row(id: id, title: titles[id] ?? id, byStore: list, usual: top?.key ?? "", usualCount: top?.value ?? 0)
        }
    }

    private func isOutside(_ p: String) -> Bool { p == "Outside suppliers" || p == "Market" || p == "No fixed supplier" }

    var body: some View {
        let all = rows()
        let ids = Set(summary.stores.map { $0.id })
        let links = engine.supplyLinks().filter { ids.contains($0.buyerID) || ids.contains($0.supplierID) }
        // Inputs where every store buys outside need no row of their own.
        let active = all.filter { r in !(r.exceptions.isEmpty && isOutside(r.usual) && r.id != "goods" && r.id != "repair") }
        let quiet = all.filter { r in r.exceptions.isEmpty && isOutside(r.usual) && r.id != "goods" && r.id != "repair" }
        let rules = engine.chainSupplierRules(chainID: summary.id)
        if !all.isEmpty {
            LedgerSection(title: "Suppliers", trailing: { Text("\(links.count) from your own").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("The usual provider of each input across the stores, and the stores that differ. Set a chain rule to make one provider the choice for every store the chain governs; without a rule each store chooses its own. A board agreement can set goods for every company.")
                        .font(.caption).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true).padding(.bottom, 6)
                    ForEach(rules) { rule in
                        ruleBlock(rule)
                        Hairline()
                    }
                    ForEach(Array(active.enumerated()), id: \.element.id) { n, r in
                        if n > 0 { Hairline() }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(r.title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.ivoryFaint)
                                    Text(r.usual).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                                }
                                Spacer(minLength: 8)
                                Text("\(r.usualCount) of \(r.byStore.count) stores").font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.ivoryMuted)
                            }
                            ForEach(Array(r.exceptions.prefix(8)), id: \.storeID) { x in
                                NavigationLink(value: CompanyRoute.companyAt(x.storeID, .operations)) {
                                    GroupLinkRow(title: x.store, sub: "Exception: \(x.provider)", subTint: Theme.caution)
                                }.buttonStyle(.plain)
                            }
                            if r.exceptions.count > 8 { Text("and \(r.exceptions.count - 8) more stores differ").font(.caption2).foregroundStyle(Theme.ivoryFaint) }
                        }.padding(.vertical, 8)
                    }
                    Hairline()
                    setRuleMenu(all)
                    if !quiet.isEmpty {
                        Hairline()
                        Text("All stores buy outside: " + quiet.map { $0.title.lowercased() }.joined(separator: ", ") + ". Open a store's Operations > Suppliers to compare your own companies and business customers.")
                            .font(.caption2).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                    }
                    ForEach(Array(links.enumerated()), id: \.element.id) { n, l in
                        Hairline()
                        let buyer = engine.state.company(l.buyerID)?.name ?? "Store"
                        let supplier = engine.state.company(l.supplierID)?.name ?? "Supplier"
                        NavigationLink(value: CompanyRoute.companyAt(l.buyerID, .operations)) {
                            GroupLinkRow(title: "\(supplier) → \(buyer)",
                                         sub: "\(IntercompanySupply.kind(l.kindID)?.name ?? l.kindID) · \(IntercompanySupply.modeName(l.mode)) · \(Int((l.lastShare * 100).rounded()))% delivered",
                                         trailing: currency.tidyShort(l.lastSpend * l.lastShare * l.lastPriceFactor * 52) + " / yr",
                                         subTint: l.lastShare < 0.9 ? Theme.loss : Theme.ivoryFaint)
                        }.buttonStyle(.plain)
                    }
                }
            }
            .confirmAction($pending)
        }
    }

    // MARK: Chain rule

    @ViewBuilder private func ruleBlock(_ rule: ChainSupplierRule) -> some View {
        let following = rule.plan.lines.filter { !$0.changes && !$0.free }.count
        let kept = rule.plan.lines.filter { $0.changes && $0.reason != nil && !$0.free }
        let free = rule.plan.lines.filter { $0.free }
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Chain rule · \(rule.title)").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.ivoryFaint)
                    Text(rule.providerName).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                }
                Spacer(minLength: 8)
                Chip(text: "Mandatory", tint: Theme.gold)
            }
            Text("\(following) of \(rule.plan.lines.count) stores follow it" + (kept.isEmpty ? "" : "; \(kept.count) keep their own") + (free.isEmpty ? "" : "; \(free.count) franchised decide themselves") + ".")
                .font(.system(size: 11)).foregroundStyle(kept.isEmpty ? Theme.ivoryFaint : Theme.caution)
            ForEach(kept.prefix(8)) { l in
                NavigationLink(value: CompanyRoute.companyAt(l.storeID, .operations)) {
                    GroupLinkRow(title: l.storeName, sub: "Keeps its own, locked by the rule: \(l.reason ?? "")", subTint: Theme.caution)
                }.buttonStyle(.plain)
            }
            HStack(spacing: 12) {
                if !kept.isEmpty || rule.plan.changing > 0 {
                    Button("Try the stores that differ again") {
                        let r = store.act { $0.setChainSupplier(chainID: summary.id, input: rule.input, to: rule.change) }
                        report(r, rule.providerName)
                    }.buttonStyle(QuietButtonStyle(tint: Theme.gold))
                }
                Button("Each store decides") {
                    pending = PendingAction(title: "Release the \(rule.title.lowercased()) rule?", message: "The chain no longer fixes this input. Every store keeps the provider it has now and may change it on its own.", button: "Release") {
                        store.act { $0.releaseChainSupplier(chainID: summary.id, input: rule.input) }
                        store.show("Each store now decides its own \(rule.title.lowercased()).", tone: "n")
                    }
                }.buttonStyle(QuietButtonStyle(tint: Theme.ivoryMuted))
                Spacer(minLength: 0)
            }
        }.padding(.vertical, 8)
    }

    @ViewBuilder private func setRuleMenu(_ rows: [Row]) -> some View {
        Menu {
            ForEach(rows) { r in
                Menu(r.title) {
                    ForEach(engine.chainSupplierChoices(chainID: summary.id, input: r.id)) { c in
                        Button("\(c.name) · \(c.using + c.wouldSwitch) of \(c.total) stores can" + (c.cannot > 0 ? ", \(c.cannot) cannot" : "")) { confirmRule(r, c) }
                    }
                }
            }
        } label: {
            Text("Set a chain-wide provider").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold)
        }.padding(.vertical, 8)
    }

    private func confirmRule(_ r: Row, _ c: ChainSupplierChoice) {
        let plan = engine.chainSupplierPlan(chainID: summary.id, input: r.id, to: c.change)
        var lines = ["\(r.title): \(c.name) for every store the chain governs.",
                     "\(plan.changing) store\(plan.changing == 1 ? "" : "s") will switch; \(plan.lines.filter { !$0.changes && !$0.free }.count) already use it."]
        for l in plan.lines where l.changes && l.reason != nil && !l.free { lines.append("\(l.storeName) cannot and keeps its own: \(l.reason ?? "")") }
        let franchised = plan.lines.filter { $0.free }.count
        if franchised > 0 { lines.append("\(franchised) franchised unit\(franchised == 1 ? "" : "s") are not bound: their agreement does not cover this.") }
        lines.append("The rule is mandatory: stores cannot choose another provider for this input until you release it. Prices and terms are each store's own, from its own relationship and size.")
        pending = PendingAction(title: "Make \(c.name) the chain's choice?", message: lines.joined(separator: "\n"), button: "Set chain rule") {
            let result = store.act { $0.setChainSupplier(chainID: summary.id, input: r.id, to: c.change) }
            report(result, c.name)
        }
    }

    private func report(_ plan: SupplyDeals.ChainPlan?, _ name: String) {
        guard let plan else { store.show("Nothing changed.", tone: "warn"); return }
        if plan.exceptions > 0 { Haptics.warning(); store.show("\(name) is the rule. \(plan.changing) switched, \(plan.exceptions) keep their own (see the list).", tone: "warn") }
        else { Haptics.success(); store.show("\(name) is the rule for all the stores it governs.", tone: "good") }
    }
}
