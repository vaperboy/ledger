import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Everything the group's live companies buy from suppliers, in one list grouped by what is supplied (not by vendor). A row is one kind of
/// purchase across the companies that make it: who supplies it (the usual supplier and how many others), quality and reliability in words
/// (reliability shows the weakest), and the week's cost across the group against the week before. A tap opens the companies behind the row,
/// each with a button to compare its suppliers. It owns its scroll area unless `embedded` (the Suppliers tab of Group has its own scroll).
struct GroupSupplierDirectory: View {
    @EnvironmentObject var store: GameStore
    var embedded: Bool = false
    @State private var picked: DirectoryPick?

    struct DirectoryPick: Identifiable, Equatable { var id: String }

    /// One company's line of a purchase.
    fileprivate struct Use {
        var companyID: Int
        var companyName: String
        var currency: Currency
        var row: SupplyRow
    }

    /// One kind of purchase across the group.
    fileprivate struct Entry: Identifiable {
        var id: String
        var group: String
        var kind: String
        var uses: [Use]
        var weeklyHome: Double
        var beforeHome: Double
        var priced: Bool
    }

    /// The purchases of one group heading.
    fileprivate struct DirectoryGroup: Identifiable {
        var id: String { name }
        var name: String
        var entries: [Entry]
    }

    var body: some View {
        if let e = store.engine {
            let groups: [DirectoryGroup] = Self.groups(e)
            Group {
                if embedded {
                    VStack(alignment: .leading, spacing: Theme.Space.xl) { list(groups, e) }
                } else {
                    ScrollScreen(spacing: Theme.Space.xl) { list(groups, e) }
                }
            }
            .centerSheet(item: $picked, category: .medium, tone: .info) { (p: DirectoryPick) in detail(p.id) }
        }
    }

    // MARK: List

    @ViewBuilder private func list(_ groups: [DirectoryGroup], _ e: GameEngine) -> some View {
        if groups.isEmpty {
            EmptyState(glyph: Glyph.suppliers, title: "Nothing bought from suppliers yet",
                       message: "What your open companies buy shows here, grouped by what is supplied.")
        } else {
            let home: Currency = e.homeCurrency
            summary(groups, home)
            ForEach(groups) { (g: DirectoryGroup) in
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text(g.name).capsLabel(Theme.ivoryFaint).padding(.horizontal, 2)
                    VStack(spacing: 0) {
                        ForEach(Array(g.entries.enumerated()), id: \.element.id) { (n: Int, en: Entry) in
                            if n > 0 { Hairline() }
                            row(en, home)
                        }
                    }
                    .padding(.horizontal, Theme.Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassSurface()
                }
            }
        }
    }

    private func summary(_ groups: [DirectoryGroup], _ home: Currency) -> some View {
        let all: [Entry] = groups.flatMap { $0.entries }
        let priced: [Entry] = all.filter { $0.priced }
        let now: Double = priced.reduce(0) { $0 + $1.weeklyHome }
        let before: Double = priced.reduce(0) { $0 + $1.beforeHome }
        let companies: Int = Set(all.flatMap { $0.uses.map { $0.companyID } }).count
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Bought by the group").capsLabel(Theme.ivoryFaint)
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                SupplyCost(now: priced.isEmpty ? nil : now, before: before, currency: home, step: .figure)
                if !priced.isEmpty { Text("a week").textStyle(.caption, tint: Theme.inkFaint) }
            }
            Text("\(all.count) kinds of purchase across \(companies) \(companies == 1 ? "company" : "companies"). Costs are set against last week.")
                .textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface()
    }

    private func row(_ en: Entry, _ home: Currency) -> some View {
        let who: String = Self.supplierSummary(en)
        let count: Int = en.uses.count
        return Button {
            Haptics.tap()
            picked = DirectoryPick(id: en.id)
        } label: {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(en.kind.tidyText).textStyle(.headline).lineLimit(2).multilineTextAlignment(.leading)
                    Text("\(count) \(count == 1 ? "company" : "companies") · \(who)").textStyle(.caption, tint: Theme.inkSoft).lineLimit(2).multilineTextAlignment(.leading)
                    SupplyWords(quality: Self.usualQuality(en), reliability: Self.weakestReliability(en))
                }
                Spacer(minLength: Theme.Space.s)
                VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                    SupplyCost(now: en.priced ? en.weeklyHome : nil, before: en.beforeHome, currency: home)
                    if en.priced { Text("a week").textStyle(.caption, tint: Theme.inkFaint) }
                }
            }
            .padding(.vertical, Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("group-supply-\(en.id)")
    }

    // MARK: Data

    fileprivate static func groups(_ e: GameEngine) -> [DirectoryGroup] {
        let home: Currency = e.homeCurrency
        var byKey: [String: Entry] = [:]
        var order: [String] = []
        for co in e.state.liveCompanies {
            let cur: Currency = e.currency(for: co)
            let scale: Double = home.rate > 0 ? cur.rate / home.rate : 1
            for g in e.supplyLines(companyID: co.id) {
                for r in g.rows {
                    let key: String = r.group + "|" + r.kind
                    let use = Use(companyID: co.id, companyName: co.name, currency: cur, row: r)
                    let now: Double = (r.weekly ?? 0) * scale
                    let before: Double = (r.weeklyBefore ?? r.weekly ?? 0) * scale
                    if var en = byKey[key] {
                        en.uses.append(use)
                        if r.weekly != nil { en.weeklyHome += now; en.beforeHome += before; en.priced = true }
                        byKey[key] = en
                    } else {
                        byKey[key] = Entry(id: key, group: r.group, kind: r.kind, uses: [use], weeklyHome: now, beforeHome: before, priced: r.weekly != nil)
                        order.append(key)
                    }
                }
            }
        }
        var names: [String] = SupplyCatalogue.groups
        for k in order { if let g = byKey[k]?.group, !names.contains(g) { names.append(g) } }
        var out: [DirectoryGroup] = []
        for name in names {
            let entries: [Entry] = order.compactMap { byKey[$0] }.filter { $0.group == name }.sorted { (a: Entry, b: Entry) -> Bool in
                a.weeklyHome != b.weeklyHome ? a.weeklyHome > b.weeklyHome : a.kind < b.kind
            }
            if !entries.isEmpty { out.append(DirectoryGroup(name: name, entries: entries)) }
        }
        return out
    }

    /// The supplier most companies use for this purchase, and how many others there are.
    private static func supplierSummary(_ en: Entry) -> String {
        let counts: [String: Int] = Dictionary(en.uses.map { ($0.row.current, 1) }, uniquingKeysWith: +)
        let ranked: [(key: String, value: Int)] = counts.sorted { (a: (key: String, value: Int), b: (key: String, value: Int)) -> Bool in
            a.value != b.value ? a.value > b.value : a.key < b.key
        }
        guard let top = ranked.first else { return "" }
        let others: Int = ranked.count - 1
        return others == 0 ? top.key : "\(top.key) and \(others) other\(others == 1 ? "" : "s")"
    }

    private static func usualQuality(_ en: Entry) -> String {
        let counts: [String: Int] = Dictionary(en.uses.map { ($0.row.quality, 1) }, uniquingKeysWith: +)
        return counts.max { (a: (key: String, value: Int), b: (key: String, value: Int)) -> Bool in a.value != b.value ? a.value < b.value : a.key > b.key }?.key ?? "Solid"
    }

    private static func weakestReliability(_ en: Entry) -> String {
        let rank: [String: Int] = ["Patchy": 0, "Not yet tested": 1, "Steady": 2, "Dependable": 3]
        return en.uses.map { $0.row.reliability }.min { (rank[$0] ?? 2) < (rank[$1] ?? 2) } ?? "Steady"
    }

    // MARK: Popup

    @ViewBuilder private func detail(_ id: String) -> some View {
        if let e = store.engine, let en = Self.groups(e).flatMap({ $0.entries }).first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text(en.group).popupText(.caption)
                ForEach(Array(en.uses.enumerated()), id: \.offset) { (n: Int, u: Use) in
                    if n > 0 { Hairline() }
                    use(u)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .centerSheetTitle(en.kind)
        }
    }

    private func use(_ u: Use) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(u.companyName.tidyText).textStyle(.headline)
                    Text("\(u.row.title) · \(u.row.current)").textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.Space.s)
                SupplyCost(now: u.row.weekly, before: u.row.weeklyBefore, currency: u.currency, step: .body)
            }
            SupplyWords(quality: u.row.quality, reliability: u.row.reliability)
            if let note = u.row.governed ?? u.row.note { Text(note).popupText(.risk) }
            QuietButton(title: "Compare suppliers", fullWidth: true) {
                picked = nil
                store.openCompany(u.companyID, section: .operations, part: CompanyTab.supply.rawValue)
            }
        }
    }
}
