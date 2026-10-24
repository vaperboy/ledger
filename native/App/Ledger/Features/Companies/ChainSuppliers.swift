import SwiftUI
import GameCore
import Finance
import Businesses
import Simulation

/// The chain's view of the same Suppliers record as a store's Operations > Suppliers: for each input, who the stores use, which provider is
/// the usual one and which stores differ (the exceptions). The engine has no chain-wide supplier rule (only the board's goods agreement, which
/// covers every company), so the choice itself is made in each store; each exception opens that store's Suppliers section.
struct ChainSupplyOverview: View {
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
        if !all.isEmpty {
            LedgerSection(title: "Suppliers", trailing: { Text("\(links.count) from your own").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("The usual provider of each input across the stores, and the stores that differ. Each store chooses its own provider; a board agreement can set goods for every company.")
                        .font(.caption).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true).padding(.bottom, 6)
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
        }
    }
}
