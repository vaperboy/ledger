import SwiftUI
import GameCore
import Businesses
import Simulation

/// The Team tab: every person who works for you in one list, grouped by the company they belong to, each with a role and a scope badge
/// (store, chain, region, group). A row opens the owning company's Team section, where hiring, promotion, pay and letting go happen.
struct TeamView: View {
    @EnvironmentObject var store: GameStore
    @State private var filter = "all"

    struct Entry: Identifiable {
        var id: String
        var name: String
        var role: String
        var scope: String
        var wage: Double
        var companyID: Int?
    }

    private static let scopes = ["all", "store", "chain", "region", "group"]

    var body: some View {
        NavigationStack {
            if let e = store.engine {
                let cos = e.state.companies.filter { $0.status.isLive }
                let groupEntries = groupLevel(e)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Space.l) {
                        Text("Team").font(.serifTitle(28))
                        SectionTabs(items: Self.scopes, title: { $0.prefix(1).uppercased() + $0.dropFirst() }, selection: $filter).padding(.horizontal, -Theme.Space.margin)
                        let shownGroup = groupEntries.filter { filter == "all" || $0.scope == filter }
                        if !shownGroup.isEmpty {
                            LedgerSection("Group and chains") {
                                VStack(spacing: 0) {
                                    ForEach(Array(shownGroup.enumerated()), id: \.element.id) { n, en in
                                        if n > 0 { Hairline() }
                                        Button { store.tab = .group; Haptics.tap() } label: { row(en, e, nil) }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        ForEach(cos, id: \.id) { co in
                            let list = entries(co, e).filter { filter == "all" || $0.scope == filter }
                            if !list.isEmpty {
                                LedgerSection(title: co.name, trailing: { Text("\(e.tradeName(co)) · \(e.cityName(co))").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
                                    VStack(spacing: 0) {
                                        ForEach(Array(list.enumerated()), id: \.element.id) { n, en in
                                            if n > 0 { Hairline() }
                                            Button { openTeam(co.id) } label: { row(en, e, co) }.buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                        if cos.isEmpty && groupEntries.isEmpty {
                            Text("No one works for you yet. Open a company, then hire from its Team section.").font(.bodyText).foregroundStyle(Theme.ivoryMuted)
                        }
                    }
                    .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                    .frame(maxWidth: 900).frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .ledgerBackground()
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
            }
        }
    }

    private func openTeam(_ id: Int) {
        Haptics.tap()
        store.companySection = .staff
        store.openCompanyID = id
        store.tab = .company
    }

    @ViewBuilder private func row(_ en: Entry, _ e: GameEngine, _ co: Company?) -> some View {
        HStack(spacing: Theme.Space.m) {
            IconBadge(symbol: "person.fill", tint: Theme.ivoryMuted, size: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(en.name).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                HStack(spacing: 6) {
                    Text(en.role).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                    Chip(text: en.scope, tint: en.scope == "store" ? Theme.ivoryMuted : Theme.gold)
                }
            }
            Spacer(minLength: 8)
            if en.wage > 0 {
                Text(co.map { store.short(en.wage, in: $0) } ?? store.short(en.wage)).font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.ivory)
            }
            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func roleName(_ id: String) -> String { id.prefix(1).uppercased() + id.dropFirst() }

    /// The store manager, the management roles above the manager and the workers of one company.
    private func entries(_ co: Company, _ e: GameEngine) -> [Entry] {
        var out: [Entry] = []
        if let mid = co.managerID, let p = e.state.people[mid] {
            out.append(Entry(id: "m\(co.id)", name: p.name, role: co.type == "hold" ? "Manager" : "Store manager", scope: "store", wage: co.managerMonthlyWage, companyID: co.id))
        }
        for slot in e.teamSlots(companyID: co.id) where slot.personID != nil {
            let scope = slot.key == "ceo" ? (co.type == "hold" ? "group" : "store") : (slot.key == "reg" ? "region" : "store")
            out.append(Entry(id: "t\(co.id)-\(slot.id)", name: slot.personID.flatMap { e.state.people[$0]?.name } ?? slot.title, role: slot.title, scope: scope, wage: slot.monthlyWage, companyID: co.id))
        }
        for m in co.staff {
            out.append(Entry(id: "s\(co.id)-\(m.id)", name: e.state.people[m.id]?.name ?? roleName(m.role), role: roleName(m.role), scope: "store", wage: m.monthlyWage, companyID: co.id))
        }
        return out
    }

    /// Group managing director, chain CEOs and managers, regional managers: the posts that belong to no single company.
    private func groupLevel(_ e: GameEngine) -> [Entry] {
        var out: [Entry] = []
        let md = e.groupManagingDirector
        if !md.isNull, let p = e.state.people[md["npc"].int] {
            out.append(Entry(id: "md", name: p.name, role: "Group managing director", scope: "group", wage: md["wage"].double, companyID: nil))
        }
        for ch in e.state.rest["chains"]?.array ?? [] {
            let rec = ch["ceo56"]
            if !rec.isNull, let p = e.state.people[rec["npc"].int] {
                let chainName = ch["name"].string.isEmpty ? "Chain" : ch["name"].string
                out.append(Entry(id: "cc\(ch["id"].int)", name: p.name, role: "Chain CEO · " + chainName, scope: "chain", wage: rec["wage"].double, companyID: nil))
            }
        }
        for r in e.regionalManagers {
            guard let p = e.state.people[r["npc"].int] else { continue }
            let scope = r["scope"].string
            let isRegion = scope.split(separator: ":").count >= 3
            out.append(Entry(id: "rm\(r["id"].int)", name: p.name, role: isRegion ? "Regional manager" : "Chain manager", scope: isRegion ? "region" : "chain", wage: r["wage"].double, companyID: nil))
        }
        return out
    }
}
