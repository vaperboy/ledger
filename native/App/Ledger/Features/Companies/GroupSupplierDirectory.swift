import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

// Every supplier the group's companies use, in the same groups, rows and supplier screen as each company's own list.
struct GroupSupplierDirectory: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject private var market: SupplyMarketStore = SupplyMarketStore.shared
    var embedded: Bool = false
    @State private var opened: Opened?

    struct Opened: Identifiable, Hashable {
        var companyID: Int
        var subject: SupplierSubject
        var id: String { "\(companyID):" + subject.id }
    }

    fileprivate struct Entry: Identifiable {
        var companyID: Int
        var facts: SupplierFacts
        var weeklyHome: Double?
        var beforeHome: Double?
        var id: String { "\(companyID):" + facts.id }
    }

    fileprivate struct DirectoryGroup: Identifiable {
        var id: String { name }
        var name: String
        var entries: [Entry]
    }

    var body: some View {
        if let e = store.engine {
            let groups: [DirectoryGroup] = Self.groups(e, market: market)
            Group {
                if embedded {
                    VStack(alignment: .leading, spacing: Theme.Space.xl) { list(groups, e) }
                } else {
                    ScrollScreen(spacing: Theme.Space.xl) { list(groups, e) }
                }
            }
            .navigationDestination(item: $opened) { (o: Opened) in
                SupplierProfileScreen(companyID: o.companyID, subject: o.subject)
            }
            .task { market.sync(store) }
        }
    }

    @ViewBuilder private func list(_ groups: [DirectoryGroup], _ e: GameEngine) -> some View {
        if groups.isEmpty {
            EmptyState(glyph: Glyph.suppliers, title: "Nothing bought from suppliers yet",
                       message: "What your open companies buy shows here, grouped like each company's own supplier list.")
        } else {
            summary(groups, e.homeCurrency)
            ForEach(groups) { (g: DirectoryGroup) in
                PageGroup("What the group buys: " + g.name.lowercased()) {
                    ForEach(Array(g.entries.enumerated()), id: \.element.id) { (n: Int, en: Entry) in
                        if n > 0 { RowRule(inset: 0) }
                        SupplierListRow(facts: en.facts, identifier: "group-supply-" + en.id) {
                            opened = Opened(companyID: en.companyID, subject: en.facts.subject)
                        }
                    }
                }
            }
        }
    }

    private func summary(_ groups: [DirectoryGroup], _ home: Currency) -> some View {
        let all: [Entry] = groups.flatMap { $0.entries }
        let priced: [Entry] = all.filter { $0.weeklyHome != nil }
        let now: Double = priced.reduce(0) { $0 + ($1.weeklyHome ?? 0) }
        let before: Double = priced.reduce(0) { $0 + ($1.beforeHome ?? $1.weeklyHome ?? 0) }
        let companies: Int = Set(all.map { $0.companyID }).count
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Bought by the group").capsLabel(Theme.ivoryFaint)
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                SupplyCost(now: priced.isEmpty ? nil : now, before: before, currency: home, step: .figure)
                if !priced.isEmpty { Text("a week").textStyle(.caption, tint: Theme.inkFaint) }
            }
            Text("\(all.count) suppliers across \(companies) \(companies == 1 ? "company" : "companies"). Costs are set against last week.")
                .textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface()
    }

    // Built with the company screen's own facts, so the rows read and behave the same.
    @MainActor fileprivate static func groups(_ e: GameEngine, market: SupplyMarketStore) -> [DirectoryGroup] {
        let home: Currency = e.homeCurrency
        var byGroup: [String: [Entry]] = [:]
        var names: [String] = SupplyCatalogue.groups
        for co in e.state.liveCompanies {
            let cur: Currency = e.currency(for: co)
            let scale: Double = home.rate > 0 ? cur.rate / home.rate : 1
            let lines: [SupplyGroup] = e.supplyLines(companyID: co.id)
            let rows: [SupplyRow] = lines.flatMap { (g: SupplyGroup) -> [SupplyRow] in g.rows }
            let inputs: [SupplierInput] = e.supplierInputs(companyID: co.id)
            for g in lines {
                if !names.contains(g.name) { names.append(g.name) }
                for r in g.rows {
                    guard var f = SupplierFacts.make(e, co, .line(r.id), market: market, rows: rows, inputs: inputs) else { continue }
                    f.what = co.name + " \u{00B7} " + f.what
                    byGroup[g.name, default: []].append(Entry(companyID: co.id, facts: f, weeklyHome: r.weekly.map { $0 * scale },
                                                              beforeHome: r.weeklyBefore.map { $0 * scale }))
                }
            }
        }
        return names.compactMap { (n: String) -> DirectoryGroup? in
            guard let list = byGroup[n], !list.isEmpty else { return nil }
            return DirectoryGroup(name: n, entries: list)
        }
    }
}
